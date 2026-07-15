import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  assertPreflightReady,
  buildPreflightSummary,
  filterPorepSourceChanges,
  parsePorepSourceChanges,
  readDeploymentRecord,
  type ContractCheck,
  type PreflightFacts
} from "../src/preflight.js";

const addresses = Object.fromEntries(
  Array.from({ length: 8 }, (_, index) => [index + 1, `0x${String(index + 1).padStart(40, "0")}`])
);

function requiredContract(address: string): ContractCheck {
  return {
    address,
    code: "present",
    deploymentRequired: true,
    deploymentAddress: address,
    matchesDeployment: true,
    abiPath: "/tmp/contract.json",
    abiPresent: true
  };
}

function readyFacts(): PreflightFacts {
  return {
    boostBranch: "porep-v2-e2e-harness",
    boostCommit: "78c8b8b",
    porepSourceDir: "/tmp/porep",
    porepBranch: "activate-evidence-payment-flow",
    porepCommit: "803942a5f439e0a588da245727197ca22546bb1f",
    expectedPorepCommit: "803942a5f439e0a588da245727197ca22546bb1f",
    porepDirty: [],
    deploymentRecordPath: "/tmp/porep/deployments/devnet/latest.json",
    deploymentRecordStatus: "valid",
    deploymentRecordChainId: 31415926,
    devnetStatus: "available",
    chainId: 31415926,
    expectedChainId: 31415926,
    binaries: { forge: true, cast: true, docker: true, node: true },
    requiredEnv: { PRIVATE_KEY_TEST: "[set]", POREP_MARKET: "[set]", USDC_TOKEN: "[set]" },
    contracts: {
      poRepMarket: requiredContract(addresses[1]!),
      dataCapEvidenceAdapter: requiredContract(addresses[2]!),
      spRegistry: requiredContract(addresses[3]!),
      validatorFactory: requiredContract(addresses[4]!),
      filecoinPay: requiredContract(addresses[5]!),
      sliOracle: requiredContract(addresses[6]!),
      metaAllocator: requiredContract(addresses[7]!),
      usdcToken: {
        address: addresses[8]!,
        code: "present",
        deploymentRequired: false,
        abiPath: "/tmp/MockUSDC.json",
        abiPresent: true
      }
    },
    runDir: "/tmp/run"
  };
}

test("buildPreflightSummary prints commits, devnet status, env redaction, and artifact dir", () => {
  const summary = buildPreflightSummary({
    ...readyFacts(),
    porepCommit: "36e8ddb",
    porepDirty: ["M test/PoRepMarket.t.sol"],
    devnetStatus: "unavailable",
    binaries: { forge: true, cast: true, docker: false, node: true },
    requiredEnv: { PRIVATE_KEY_TEST: "[set]", POREP_MARKET: "[set]", USDC_TOKEN: "[missing]" }
  });

  assert.match(summary, /Boost: porep-v2-e2e-harness @ 78c8b8b/);
  assert.match(summary, /PoRep: activate-evidence-payment-flow @ 36e8ddb/);
  assert.match(summary, /PoRep dirty: M test\/PoRepMarket\.t\.sol/);
  assert.match(summary, /docker: missing/);
  assert.match(summary, /PRIVATE_KEY_TEST=\[set\]/);
  assert.doesNotMatch(summary, /0xabc123/);
  assert.match(summary, /Run artifacts: \/tmp\/run/);
});

test("assertPreflightReady reports every strict preflight failure", () => {
  const facts = readyFacts();
  facts.chainId = 1;
  facts.porepCommit = "wrong";
  facts.porepDirty = [" M src/PoRepMarket.sol"];
  facts.requiredEnv.USDC_TOKEN = "[missing]";
  facts.binaries.docker = false;
  facts.devnetStatus = "unavailable";
  const poRepMarket = facts.contracts.poRepMarket!;
  facts.contracts.poRepMarket = {
    address: poRepMarket.address,
    code: "missing",
    deploymentRequired: true,
    deploymentAddress: "0x0000000000000000000000000000000000000002",
    matchesDeployment: false,
    abiPath: "/tmp/porep/out/PoRepMarket.sol/PoRepMarket.json",
    abiPresent: false
  };

  assert.throws(
    () => assertPreflightReady(facts),
    /chainId: expected 31415926, got 1[\s\S]*porepCommit: expected 803942a5f439e0a588da245727197ca22546bb1f, got wrong[\s\S]*porepDirty: source-bearing local changes[\s\S]*requiredEnv\.USDC_TOKEN: missing[\s\S]*binaries\.docker: missing[\s\S]*devnetStatus: unavailable[\s\S]*contracts\.poRepMarket\.code: missing[\s\S]*contracts\.poRepMarket\.abi: missing[\s\S]*contracts\.poRepMarket\.deploymentAddress: mismatch/
  );
});

test("assertPreflightReady accepts matching V2 deployment facts", () => {
  assert.doesNotThrow(() => assertPreflightReady(readyFacts()));
});

test("readDeploymentRecord distinguishes absent and malformed records", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-deployment-record-"));
  const path = join(dir, "latest.json");

  assert.equal(readDeploymentRecord(path).status, "missing");
  writeFileSync(path, "{not-json\n");
  assert.equal(readDeploymentRecord(path).status, "malformed");
});

test("readDeploymentRecord accepts numeric and decimal-string chain IDs", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-deployment-chain-"));
  const path = join(dir, "latest.json");

  writeFileSync(path, '{"chainId":31415926}\n');
  assert.equal(readDeploymentRecord(path).chainId, 31415926);
  writeFileSync(path, '{"chainId":"31415926"}\n');
  assert.equal(readDeploymentRecord(path).chainId, 31415926);
});

test("readDeploymentRecord classifies absent and malformed chain IDs", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-deployment-chain-"));
  const path = join(dir, "latest.json");

  writeFileSync(path, '{}\n');
  assert.equal(readDeploymentRecord(path).chainId, "missing");
  for (const value of [null, 31415926.5, "not-a-chain", "31415926.0", -1]) {
    writeFileSync(path, `${JSON.stringify({ chainId: value })}\n`);
    assert.equal(readDeploymentRecord(path).chainId, "malformed");
  }
});

test("assertPreflightReady rejects absent, malformed, and wrong deployment chain IDs", () => {
  for (const chainId of ["missing", "malformed", 1] as const) {
    assert.throws(
      () => assertPreflightReady({ ...readyFacts(), deploymentRecordChainId: chainId }),
      new RegExp(`deploymentRecord\\.chainId: expected 31415926, got ${chainId}`)
    );
  }
});

test("assertPreflightReady rejects absent and malformed deployment records", () => {
  for (const status of ["missing", "malformed"] as const) {
    assert.throws(
      () => assertPreflightReady({ ...readyFacts(), deploymentRecordStatus: status }),
      new RegExp(`deploymentRecord: ${status}`)
    );
  }
});

test("assertPreflightReady rejects a missing required deployment entry", () => {
  const facts = readyFacts();
  const { deploymentAddress: _address, matchesDeployment: _matches, ...withoutDeployment } = facts.contracts.filecoinPay!;
  facts.contracts.filecoinPay = withoutDeployment;

  assert.throws(
    () => assertPreflightReady(facts),
    /contracts\.filecoinPay\.deploymentAddress: missing/
  );
});

test("generated devnet deployment JSON is excluded from PoRep source dirtiness", () => {
  assert.deepEqual(filterPorepSourceChanges([
    " M deployments/devnet/latest.json",
    "?? deployments/devnet/run-1.json",
    " M src/PoRepMarket.sol"
  ]), [" M src/PoRepMarket.sol"]);
});

test("generated deployment JSON stays excluded when it is the first status line", () => {
  assert.deepEqual(parsePorepSourceChanges(" M deployments/devnet/latest.json\n?? deployments/devnet/run-1.json\n"), []);
});

test("USDC requires code and ABI but no PoRep deployment entry", () => {
  const facts = readyFacts();
  assert.equal(facts.contracts.usdcToken?.deploymentAddress, undefined);
  assert.doesNotThrow(() => assertPreflightReady(facts));
});
