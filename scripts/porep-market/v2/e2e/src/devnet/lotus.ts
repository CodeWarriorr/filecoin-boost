import type { ScenarioContext } from "../runtime.js";
import { envNumber } from "../runtime.js";
import { run, sleep } from "../shell.js";
import { dockerExecOk } from "./docker.js";
import { currentLotusEpoch } from "./boost.js";

export async function waitForProviderClaim(
  context: ScenarioContext,
  input: { allocationId: bigint; targetStartEpoch?: bigint }
): Promise<{ claimId: bigint }> {
  const minerId = envNumber(context, "MINER_ID", 1000);
  const minerActor = `t0${minerId}`;
  const maxAttempts = envNumber(context, "CLAIM_MAX_ATTEMPTS", 900);
  const pollSeconds = envNumber(context, "CLAIM_POLL_SECONDS", 1);

  console.log("=== Wait for V2 claim ===");
  console.log(`  Allocation: ${input.allocationId}`);
  console.log(`  Miner:      ${minerActor}`);

  publishPrecommit(context);

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (claimExists(context, minerActor, input.allocationId)) {
      console.log(`  Claim ${input.allocationId} confirmed on-chain`);
      console.log("=== V2 claim confirmed ===");
      return { claimId: input.allocationId };
    }

    maybePublishBatches(context, input.targetStartEpoch);
    if (attempt === 1 || attempt % 30 === 0) {
      console.log(`  [${attempt}/${maxAttempts}] waiting... (${pollSeconds}s)`);
    }
    await sleep(pollSeconds * 1000);
  }

  throw new Error(`claim ${input.allocationId} not found after ${maxAttempts * pollSeconds}s`);
}

function claimExists(context: ScenarioContext, minerActor: string, allocationId: bigint): boolean {
  const result = run("docker", ["exec", "lotus", "lotus", "filplus", "list-claims", minerActor], context.boostRoot);
  if (result.status !== 0) return false;
  return result.stdout.split(/\r?\n/).some((line) => line.trim().split(/\s+/)[0] === allocationId.toString());
}

function maybePublishBatches(context: ScenarioContext, targetStartEpoch: bigint | undefined): void {
  if (targetStartEpoch !== undefined) {
    const headEpoch = BigInt(currentLotusEpoch(context));
    if (headEpoch >= targetStartEpoch - 3n && headEpoch <= targetStartEpoch + 3n) {
      console.log(`  Target start epoch window: head=${headEpoch} target=${targetStartEpoch}`);
      publishCommit(context);
      return;
    }
  }
  publishPrecommit(context);
  publishCommit(context);
}

function publishPrecommit(context: ScenarioContext): void {
  dockerExecOk(context, "lotus-miner", ["lotus-miner", "sectors", "batching", "precommit", "--publish-now"]);
}

function publishCommit(context: ScenarioContext): void {
  dockerExecOk(context, "lotus-miner", ["lotus-miner", "sectors", "batching", "commit", "--publish-now"]);
}
