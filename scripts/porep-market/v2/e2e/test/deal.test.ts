import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { nextProposalManifest } from "../src/flows/deal.js";
import { StateStore } from "../src/state.js";
import type { ScenarioContext } from "../src/runtime.js";

test("nextProposalManifest creates unique defaults within one scenario run", () => {
  const context = testContext();

  const first = nextProposalManifest(context);
  const second = nextProposalManifest(context);

  assert.notEqual(first.location, second.location);
  assert.notEqual(first.hash, second.hash);
  assert.match(first.location, /\/proposal-1\/manifest\.json$/);
  assert.match(second.location, /\/proposal-2\/manifest\.json$/);
});

test("nextProposalManifest preserves explicit manifest env values", () => {
  const context = testContext({
    V2_MANIFEST_LOCATION: "https://example.com/custom-manifest.json",
    V2_MANIFEST_HASH: "0x1234000000000000000000000000000000000000000000000000000000000000"
  });

  const first = nextProposalManifest(context);
  const second = nextProposalManifest(context);

  assert.equal(first.location, "https://example.com/custom-manifest.json");
  assert.equal(second.location, "https://example.com/custom-manifest.json");
  assert.equal(first.hash, "0x1234000000000000000000000000000000000000000000000000000000000000");
  assert.equal(second.hash, "0x1234000000000000000000000000000000000000000000000000000000000000");
});

function testContext(env: Record<string, string | undefined> = {}): ScenarioContext {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-deal-"));
  return {
    config: {
      cwd: dir,
      envFile: join(dir, ".env"),
      rpcUrl: "http://127.0.0.1:1234/rpc/v1",
      privateKeyTest: "0x1",
      privateKeySp: "0x2",
      porepSourceDir: dir,
      runRoot: join(dir, ".runs"),
      addresses: {
        poRepMarket: "0x0000000000000000000000000000000000000001",
        spRegistry: "0x0000000000000000000000000000000000000002",
        validatorFactory: "0x0000000000000000000000000000000000000003",
        dataCapEvidenceAdapter: "0x0000000000000000000000000000000000000004",
        filecoinPay: "0x0000000000000000000000000000000000000005",
        sliOracle: "0x0000000000000000000000000000000000000006",
        metaAllocator: "0x0000000000000000000000000000000000000007",
        usdcToken: "0x0000000000000000000000000000000000000008"
      },
      requiredEnv: {},
      env
    },
    runDir: join(dir, "run-one"),
    stateFile: join(dir, "state.json"),
    boostRoot: dir,
    scriptsRoot: dir,
    state: new StateStore(join(dir, "state.json")),
    steps: []
  };
}
