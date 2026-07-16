import test from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const e2eRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

test("non-preflight CLI rejects the wrong chain before scenario dispatch", () => {
  const tempRoot = mkdtempSync(join(tmpdir(), "porep-e2e-cli-"));
  const fakeBin = join(tempRoot, "bin");
  const callsPath = join(tempRoot, "calls.log");
  const castPath = join(fakeBin, "cast");
  const privateKey = `0x${"ab".repeat(32)}`;
  const address = "0x0000000000000000000000000000000000000001";
  mkdirSync(fakeBin);

  writeFileSync(
    castPath,
    "#!/bin/bash\n" +
      "echo \"$*\" >> \"$CALLS_PATH\"\n" +
      "if [ \"${1:-}\" = chain-id ]; then echo 1; exit 0; fi\n" +
      "exit 97\n"
  );
  chmodSync(castPath, 0o755);

  const result = spawnSync(
    process.execPath,
    [join(e2eRoot, "node_modules/tsx/dist/cli.mjs"), join(e2eRoot, "src/cli.ts"), "proposal-smoke"],
    {
      cwd: e2eRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
        CALLS_PATH: callsPath,
        POREP_E2E_RUN_ROOT: join(tempRoot, "runs"),
        PRIVATE_KEY_TEST: privateKey,
        PRIVATE_KEY_SP: privateKey,
        POREP_MARKET: address,
        SP_REGISTRY: address,
        VALIDATOR_FACTORY: address,
        DATACAP_EVIDENCE_ADAPTER: address,
        FILECOIN_PAY: address,
        SLI_ORACLE: address,
        META_ALLOCATOR: address,
        USDC_TOKEN: address
      }
    }
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /expected chain ID 31415926, got 1/);
  assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, /register provider and offer/);
  assert.doesNotMatch(`${result.stdout}\n${result.stderr}`, new RegExp(privateKey, "i"));
  assert.deepEqual(readFileSync(callsPath, "utf8").trim().split("\n"), [
    "chain-id --rpc-url http://127.0.0.1:1234/rpc/v1"
  ]);
});
