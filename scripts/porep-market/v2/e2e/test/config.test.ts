import test from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig } from "../src/config.js";

test("loadConfig reads env files without exposing private key values", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-config-"));
  const envFile = join(dir, ".env");
  writeFileSync(envFile, [
    "RPC_URL=http://127.0.0.1:1234/rpc/v1",
    "PRIVATE_KEY_TEST=0xabc123",
    "PRIVATE_KEY_SP=0xdef456",
    "POREP_MARKET=0x0000000000000000000000000000000000000001",
    "SP_REGISTRY=0x0000000000000000000000000000000000000002",
    "VALIDATOR_FACTORY=0x0000000000000000000000000000000000000003",
    "DATACAP_EVIDENCE_ADAPTER=0x0000000000000000000000000000000000000004",
    "FILECOIN_PAY=0x0000000000000000000000000000000000000005",
    "SLI_ORACLE=0x0000000000000000000000000000000000000008",
    "META_ALLOCATOR=0x0000000000000000000000000000000000000006",
    "USDC_TOKEN=0x0000000000000000000000000000000000000007",
    ""
  ].join("\n"));

  const config = loadConfig({ envFile, cwd: dir, env: {} });

  assert.equal(config.rpcUrl, "http://127.0.0.1:1234/rpc/v1");
  assert.equal(config.addresses.poRepMarket, "0x0000000000000000000000000000000000000001");
  assert.equal(config.requiredEnv.PRIVATE_KEY_TEST, "[set]");
  assert.equal(config.requiredEnv.PRIVATE_KEY_SP, "[set]");
  assert.equal(config.requiredEnv.SLI_ORACLE, "[set]");
  assert.match(config.runRoot, /\/\.runs\/v2-e2e$/);
});

test("loadConfig reports missing required keys by name only", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-config-"));
  const envFile = join(dir, ".env");
  writeFileSync(envFile, "RPC_URL=http://127.0.0.1:1234/rpc/v1\n");

  assert.throws(
    () => loadConfig({ envFile, cwd: dir, env: {} }),
    /missing required env keys: PRIVATE_KEY_TEST, PRIVATE_KEY_SP, POREP_MARKET/
  );
});

test("loadConfig can report missing env keys for preflight without secret values", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-config-"));
  const envFile = join(dir, ".env");
  writeFileSync(envFile, "RPC_URL=http://127.0.0.1:1234/rpc/v1\n");

  const config = loadConfig({ envFile, cwd: dir, env: {}, allowMissing: true });

  assert.equal(config.addresses.poRepMarket, "");
  assert.equal(config.requiredEnv.PRIVATE_KEY_TEST, "[missing]");
  assert.equal(config.requiredEnv.META_ALLOCATOR, "[missing]");
});

test("loadConfig selects the managed V2 checkout before it exists", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-config-"));
  const e2eDir = join(dir, "scripts/porep-market/v2/e2e");
  const legacyV2Dir = join(dir, "scripts/porep-market/porep-market-v2");
  const pinnedV2Dir = join(dir, "scripts/porep-market/porep-market-v2-803942a5f439");
  mkdirSync(e2eDir, { recursive: true });
  mkdirSync(legacyV2Dir, { recursive: true });

  const config = loadConfig({ cwd: e2eDir, envFile: join(dir, "missing.env"), env: {}, allowMissing: true });

  assert.equal(config.porepSourceDir, pinnedV2Dir);
});

test("loadConfig uses POREP_MARKET_DIR as the only source checkout override", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-config-"));
  const explicitDir = join(dir, "explicit-porep");
  const ignoredLegacyOverride = join(dir, "ignored-legacy-override");

  const config = loadConfig({
    cwd: join(dir, "scripts/porep-market/v2/e2e"),
    envFile: join(dir, "missing.env"),
    env: {
      POREP_MARKET_DIR: explicitDir,
      POREP_MARKET_SOURCE_DIR: ignoredLegacyOverride
    },
    allowMissing: true
  });

  assert.equal(config.porepSourceDir, explicitDir);
});

test("loadConfig defaults to the versioned V2 environment file", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-config-"));
  const e2eDir = join(dir, "scripts/porep-market/v2/e2e");
  const envDir = join(dir, "scripts/porep-market");
  mkdirSync(e2eDir, { recursive: true });
  writeFileSync(join(envDir, ".env"), "POREP_MARKET=0x0000000000000000000000000000000000000001\n");
  writeFileSync(join(envDir, ".env.v2"), "POREP_MARKET=0x0000000000000000000000000000000000000002\n");

  const config = loadConfig({ cwd: e2eDir, env: {}, allowMissing: true });

  assert.equal(config.addresses.poRepMarket, "0x0000000000000000000000000000000000000002");
});

test("loadConfig keeps the devnet chain identity fixed", () => {
  const dir = mkdtempSync(join(tmpdir(), "porep-e2e-config-"));
  const config = loadConfig({
    cwd: dir,
    envFile: join(dir, "missing.env"),
    env: { POREP_E2E_CHAIN_ID: "1" },
    allowMissing: true
  });

  assert.equal(config.expectedChainId, 31415926);
});
