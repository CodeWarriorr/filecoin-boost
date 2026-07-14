import test from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig } from "../src/config.js";
import { createScenarioContext } from "../src/runtime.js";
import { artifactAbis } from "../src/contracts/abi.js";

test("artifactAbis loads contract ABIs from built artifacts", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-abis-"));
  const porep = join(dir, "porep-market");
  const scripts = join(dir, "scripts/porep-market");

  writeArtifact(porep, "SPRegistry.sol/SPRegistry.json", "isProviderRegistered");
  writeArtifact(porep, "PoRepMarket.sol/PoRepMarket.json", "getDeal");
  writeArtifact(porep, "ValidatorFactory.sol/ValidatorFactory.json", "getInstance");
  writeArtifact(porep, "Validator.sol/Validator.json", "getRailStatus");
  writeArtifact(porep, "DataCapEvidenceAdapter.sol/DataCapEvidenceAdapter.json", "getClaimIds");
  writeArtifact(porep, "SLIOracle.sol/SLIOracle.json", "getAttestation");
  writeArtifact(porep, "SLIScorer.sol/SLIScorer.json", "calculateScore");
  writeArtifact(porep, "MockUSDC.sol/MockUSDC.json", "balanceOf");
  writeArtifact(join(scripts, "filecoin-pay"), "FilecoinPayV1.sol/FilecoinPayV1.json", "getRail");

  const config = loadConfig({
    cwd: join(scripts, "v2/e2e"),
    envFile: join(dir, ".env"),
    env: {
      PRIVATE_KEY_TEST: "0x1",
      PRIVATE_KEY_SP: "0x2",
      POREP_MARKET_DIR: porep,
      POREP_MARKET: "0x0000000000000000000000000000000000000001",
      SP_REGISTRY: "0x0000000000000000000000000000000000000002",
      VALIDATOR_FACTORY: "0x0000000000000000000000000000000000000003",
      DATACAP_EVIDENCE_ADAPTER: "0x0000000000000000000000000000000000000004",
      FILECOIN_PAY: "0x0000000000000000000000000000000000000005",
      SLI_ORACLE: "0x0000000000000000000000000000000000000006",
      META_ALLOCATOR: "0x0000000000000000000000000000000000000007",
      USDC_TOKEN: "0x0000000000000000000000000000000000000008"
    }
  });
  const context = createScenarioContext(config, join(dir, "run"));

  assert.equal(Array.isArray(artifactAbis(context).poRepMarket), true);
  assert.deepEqual(artifactAbis(context).filecoinPay, [{ type: "function", name: "getRail", inputs: [], outputs: [] }]);
});

test("artifactAbis fails loudly when the configured source was not built", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-abis-missing-"));
  const config = loadConfig({
    cwd: join(dir, "scripts/porep-market/v2/e2e"),
    envFile: join(dir, ".env"),
    env: {
      PRIVATE_KEY_TEST: "0x1",
      PRIVATE_KEY_SP: "0x2",
      POREP_MARKET_DIR: join(dir, "missing-porep"),
      POREP_MARKET: "0x0000000000000000000000000000000000000001",
      SP_REGISTRY: "0x0000000000000000000000000000000000000002",
      VALIDATOR_FACTORY: "0x0000000000000000000000000000000000000003",
      DATACAP_EVIDENCE_ADAPTER: "0x0000000000000000000000000000000000000004",
      FILECOIN_PAY: "0x0000000000000000000000000000000000000005",
      SLI_ORACLE: "0x0000000000000000000000000000000000000006",
      META_ALLOCATOR: "0x0000000000000000000000000000000000000007",
      USDC_TOKEN: "0x0000000000000000000000000000000000000008"
    }
  });
  const context = createScenarioContext(config, join(dir, "run"));

  assert.throws(() => artifactAbis(context), /missing contract artifact .*SPRegistry\.json/);
});

function writeArtifact(root: string, artifactPath: string, functionName: string): void {
  const path = join(root, "out", artifactPath);
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(
    path,
    `${JSON.stringify({ abi: [{ type: "function", name: functionName, inputs: [], outputs: [] }] }, null, 2)}\n`
  );
}
