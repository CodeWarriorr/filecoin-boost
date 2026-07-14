import { Buffer } from "node:buffer";
import type { ScenarioContext } from "../runtime.js";
import { envValue } from "../runtime.js";
import { dockerExec } from "./docker.js";

export type PieceInfo = {
  pieceCid: string;
  pieceSize: bigint;
  pieceCidHex: string;
  pieceCarPath: string;
};

export function generatePieceAndAssertCommp(context: ScenarioContext): PieceInfo {
  console.log("=== Generate V2 piece ===");
  let pieceCarPath: string;

  if (envValue(context, "GENERATE_PIECE") === "1") {
    const pieceIndex = BigInt(context.state.get("GENERATED_PIECE_INDEX") ?? "0") + 1n;
    context.state.set("GENERATED_PIECE_INDEX", pieceIndex);
    const pieceDir = `/tmp/testpiece-v2-${process.pid}-${pieceIndex}`;
    pieceCarPath = `${pieceDir}/piece.car`;
    dockerExec(context, "boost", [
      "bash",
      "-c",
      `mkdir -p '${pieceDir}' && dd if=/dev/urandom bs=1 count=1500 of='${pieceDir}/rand.bin' 2>/dev/null && car create --no-wrap -f '${pieceCarPath}' '${pieceDir}/rand.bin' 2>/dev/null`
    ]);
    console.log("  generated new random CAR");
  } else {
    pieceCarPath = "/app/sample/bafykbzacec432ygday37lj2tvl3e7wl7ij46dko7cbmlndeghx6lhjkluqzhg.car";
    console.log("  using sample CAR; set GENERATE_PIECE=1 to generate a new one");
  }

  const commp = dockerExec(context, "boost", ["boostx", "commp", pieceCarPath]);
  const pieceCid = commp.match(/^CommP CID:\s+(\S+)/m)?.[1];
  const pieceSize = commp.match(/^Piece size:\s+(\d+)/m)?.[1];

  if (!pieceCid || !pieceSize) {
    throw new Error(`failed to compute CommP from ${pieceCarPath}\n${commp}`);
  }
  if (pieceCid.startsWith("Qm")) {
    throw new Error(`CIDv0 input ${pieceCid} is not supported; expected CIDv1`);
  }

  const pieceCidHex = cidToHex(pieceCid);
  context.state.set("PIECE_CID", pieceCid);
  context.state.set("PIECE_SIZE", pieceSize);
  context.state.set("PIECE_CID_HEX", pieceCidHex);
  context.state.set("PIECE_CAR_PATH", pieceCarPath);

  console.log(`  CID:  ${pieceCid}`);
  console.log(`  Size: ${pieceSize}`);
  console.log("=== V2 piece ready ===");

  return { pieceCid, pieceSize: BigInt(pieceSize), pieceCidHex, pieceCarPath };
}

function cidToHex(cid: string): string {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const char of cid.slice(1).toUpperCase()) {
    const value = alphabet.indexOf(char);
    if (value < 0) throw new Error(`unsupported base32 character in piece CID: ${char}`);
    bits += value.toString(2).padStart(5, "0");
  }

  const bytes: number[] = [];
  for (let index = 0; index + 8 <= bits.length; index += 8) {
    bytes.push(Number.parseInt(bits.slice(index, index + 8), 2));
  }
  return Buffer.from(bytes).toString("hex");
}
