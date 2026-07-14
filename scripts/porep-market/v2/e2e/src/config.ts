import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

export type AddressBook = {
  poRepMarket: string;
  spRegistry: string;
  validatorFactory: string;
  dataCapEvidenceAdapter: string;
  filecoinPay: string;
  sliOracle: string;
  metaAllocator: string;
  usdcToken: string;
};

export type E2EConfig = {
  cwd: string;
  envFile: string;
  rpcUrl: string;
  expectedChainId?: number;
  expectedPorepCommit?: string;
  deploymentRecordPath?: string;
  privateKeyTest: string;
  privateKeySp: string;
  porepSourceDir: string;
  runRoot: string;
  addresses: AddressBook;
  requiredEnv: Record<string, "[set]" | "[missing]">;
  env: Record<string, string | undefined>;
};

type LoadConfigInput = {
  cwd?: string;
  envFile?: string;
  env?: NodeJS.ProcessEnv;
  allowMissing?: boolean;
};

const REQUIRED_ENV = [
  "PRIVATE_KEY_TEST",
  "PRIVATE_KEY_SP",
  "POREP_MARKET",
  "SP_REGISTRY",
  "VALIDATOR_FACTORY",
  "DATACAP_EVIDENCE_ADAPTER",
  "FILECOIN_PAY",
  "SLI_ORACLE",
  "META_ALLOCATOR",
  "USDC_TOKEN"
] as const;

const DEVNET_CHAIN_ID = 31415926;

export function loadConfig(input: LoadConfigInput = {}): E2EConfig {
  const cwd = input.cwd ?? process.cwd();
  const envFile = input.envFile ?? resolve(cwd, "../../.env.v2");
  const mergedEnv = { ...parseEnvFile(envFile), ...(input.env ?? process.env) };
  const missing = REQUIRED_ENV.filter((key) => !mergedEnv[key]);
  const expectedPorepCommit = mergedEnv.POREP_MARKET_V2_REF ?? "803942a5f439e0a588da245727197ca22546bb1f";
  const localPorepDir = resolve(cwd, `../../porep-market-v2-${expectedPorepCommit.slice(0, 12)}`);

  if (missing.length > 0 && input.allowMissing !== true) {
    throw new Error(`missing required env keys: ${missing.join(", ")}`);
  }

  const porepSourceDir = nonEmpty(mergedEnv.POREP_MARKET_DIR) ?? localPorepDir;

  return {
    cwd,
    envFile,
    rpcUrl: mergedEnv.RPC_URL ?? "http://127.0.0.1:1234/rpc/v1",
    expectedChainId: DEVNET_CHAIN_ID,
    expectedPorepCommit,
    deploymentRecordPath: join(porepSourceDir, "deployments/devnet/latest.json"),
    privateKeyTest: getValue(mergedEnv, "PRIVATE_KEY_TEST"),
    privateKeySp: getValue(mergedEnv, "PRIVATE_KEY_SP"),
    porepSourceDir,
    runRoot: mergedEnv.POREP_E2E_RUN_ROOT ?? resolve(cwd, "../../.runs/v2-e2e"),
    addresses: {
      poRepMarket: getValue(mergedEnv, "POREP_MARKET"),
      spRegistry: getValue(mergedEnv, "SP_REGISTRY"),
      validatorFactory: getValue(mergedEnv, "VALIDATOR_FACTORY"),
      dataCapEvidenceAdapter: getValue(mergedEnv, "DATACAP_EVIDENCE_ADAPTER"),
      filecoinPay: getValue(mergedEnv, "FILECOIN_PAY"),
      sliOracle: getValue(mergedEnv, "SLI_ORACLE"),
      metaAllocator: getValue(mergedEnv, "META_ALLOCATOR"),
      usdcToken: getValue(mergedEnv, "USDC_TOKEN")
    },
    requiredEnv: Object.fromEntries(
      REQUIRED_ENV.map((key) => [key, mergedEnv[key] ? "[set]" : "[missing]"])
    ) as Record<string, "[set]" | "[missing]">,
    env: mergedEnv
  };
}

function parseEnvFile(path: string): Record<string, string> {
  if (!existsSync(path)) return {};

  const result: Record<string, string> = {};
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const index = trimmed.indexOf("=");
    if (index === -1) continue;
    const key = trimmed.slice(0, index).trim();
    const value = trimmed.slice(index + 1).trim();
    if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      result[key] = value.replace(/^['"]|['"]$/g, "");
    }
  }
  return result;
}

function getValue(env: Record<string, string | undefined>, key: string): string {
  return env[key] ?? "";
}

function nonEmpty(value: string | undefined): string | undefined {
  return value && value.length > 0 ? value : undefined;
}
