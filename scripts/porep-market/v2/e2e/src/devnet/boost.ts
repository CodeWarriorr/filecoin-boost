import type { ScenarioContext } from "../runtime.js";
import { envNumber, envValue } from "../runtime.js";
import { run, runRequired, sleep } from "../shell.js";
import { dockerExec } from "./docker.js";

type DirectImportSealingWindow = {
  startEpochOffset: number;
  boostStartEpochSealingBuffer: number;
  minerStartEpochSealingBuffer: number;
};

const BOOST_CONFIG = "/var/lib/boost/config.toml";
const MINER_CONFIG = "/var/lib/lotus-miner/config.toml";

export function ensureBoostReady(context: ScenarioContext): void {
  console.log("=== Ensure Boost ===");
  const apiPath = dockerExec(context, "boost", ["bash", "-lc", "ls /var/lib/boost/api"]);
  if (!apiPath.includes("/var/lib/boost/api")) {
    throw new Error(`Boost API file not found: ${apiPath}`);
  }
  console.log("  Boost ready");
}

export async function prepareFastSealingDevnet(context: ScenarioContext): Promise<void> {
  console.log("=== Prepare fast-sealing devnet ===");
  const targetBuffer = envNumber(context, "BOOST_DIRECT_START_EPOCH_SEALING_BUFFER", 20);
  let minerChanged = false;
  let boostChanged = false;

  const minerConfig = readContainerFile(context, "lotus-miner", MINER_CONFIG);
  const minerRequired: TomlRequirement[] = [
    { section: "Sealing", key: "StartEpochSealingBuffer", value: String(targetBuffer) },
    { section: "Sealing", key: "AggregateCommits", value: "false" },
    { section: "Sealing", key: "MinCommitBatch", value: "1" },
    { section: "Sealing", key: "MaxCommitBatch", value: "1" },
    { section: "Sealing", key: "CommitBatchWait", value: "\"1s\"" }
  ];
  for (const requirement of minerRequired) {
    if (tomlValue(minerConfig, requirement.key) !== normalizeTomlValue(requirement.value)) {
      setTomlValue(context, "lotus-miner", MINER_CONFIG, requirement);
      minerChanged = true;
    }
  }

  const boostConfig = readContainerFile(context, "boost", BOOST_CONFIG);
  const boostRequirement = { section: "Dealmaking", key: "StartEpochSealingBuffer", value: String(targetBuffer) };
  if (tomlValue(boostConfig, boostRequirement.key) !== normalizeTomlValue(boostRequirement.value)) {
    setTomlValue(context, "boost", BOOST_CONFIG, boostRequirement);
    boostChanged = true;
  }

  if (minerChanged) {
    console.log("  Restarting lotus-miner after sealing config update");
    runRequired("docker", ["compose", "-f", "docker/devnet/docker-compose.yaml", "restart", "lotus-miner"], context.boostRoot);
    await waitForContainerHealthy(context, "lotus-miner");
  }

  if (boostChanged) {
    console.log("  Restarting boost after direct import config update");
    runRequired("docker", ["compose", "-f", "docker/devnet/docker-compose.yaml", "restart", "boost"], context.boostRoot);
    await waitForContainerHealthy(context, "boost");
    runRequired("docker", ["compose", "-f", "docker/devnet/docker-compose.yaml", "restart", "booster-http", "booster-bitswap"], context.boostRoot);
    await waitForContainerHealthy(context, "booster-http");
    await waitForContainerHealthy(context, "booster-bitswap");
  }

  const window = readDirectImportSealingWindow(context, 55);
  assertDirectImportSealingWindowIsSafe(window);
  console.log(`  Boost StartEpochSealingBuffer=${window.boostStartEpochSealingBuffer}`);
  console.log(`  Miner StartEpochSealingBuffer=${window.minerStartEpochSealingBuffer}`);
  console.log("=== Fast-sealing devnet ready ===");
}

export async function importPieceIntoBoost(
  context: ScenarioContext,
  input: { allocationId: bigint; pieceCid: string; pieceCarPath: string }
): Promise<{ startEpoch: bigint; clientF4: string }> {
  const clientF4 = envValue(context, "CLIENT_FIL_ADDR") ||
    filecoinAddressFromEvmStat(dockerExec(context, "lotus", ["lotus", "evm", "stat", context.config.addresses.dataCapEvidenceAdapter]));
  if (!clientF4) throw new Error("could not resolve DataCap adapter f4 address");

  const fullnodeApi = dockerExec(context, "lotus", ["lotus", "auth", "api-info", "--perm=admin"]).split("=").slice(1).join("=").trim();
  if (!fullnodeApi) throw new Error("could not get FULLNODE_API_INFO from lotus");

  const offset = envNumber(context, "DIRECT_IMPORT_START_EPOCH_OFFSET", 55);
  const sealingWindow = readDirectImportSealingWindow(context, offset);
  assertDirectImportSealingWindowIsSafe(sealingWindow);
  console.log(`  Devnet sealing buffers: boost=${sealingWindow.boostStartEpochSealingBuffer}, miner=${sealingWindow.minerStartEpochSealingBuffer}, import offset=${offset}`);

  let headEpoch = currentLotusEpoch(context);
  let startEpoch = BigInt(headEpoch + offset);
  context.state.set("DIRECT_IMPORT_START_EPOCH", startEpoch);

  console.log("=== Import V2 piece ===");
  console.log(`  Allocation: ${input.allocationId}`);
  console.log(`  Client:     ${clientF4}`);
  console.log(`  Piece CID:  ${input.pieceCid}`);
  console.log(`  Start epoch: ${startEpoch} (head ${headEpoch} + ${offset})`);

  if (!runImportDirect(context, fullnodeApi, clientF4, input, startEpoch)) {
    console.log("  WARN: retrying import-direct in 30s");
    await sleep(30_000);
    headEpoch = currentLotusEpoch(context);
    startEpoch = BigInt(headEpoch + offset);
    context.state.set("DIRECT_IMPORT_START_EPOCH", startEpoch);
    if (!runImportDirect(context, fullnodeApi, clientF4, input, startEpoch)) {
      throw new Error("import-direct failed");
    }
  }

  console.log("=== V2 piece imported ===");
  return { startEpoch, clientF4 };
}

function runImportDirect(
  context: ScenarioContext,
  fullnodeApi: string,
  clientF4: string,
  input: { allocationId: bigint; pieceCid: string; pieceCarPath: string },
  startEpoch: bigint
): boolean {
  const result = run(
    "docker",
    [
      "exec",
      "-e",
      `FULLNODE_API_INFO=${fullnodeApi}`,
      "boost",
      "boostd",
      "import-direct",
      `--client-addr=${clientF4}`,
      `--allocation-id=${input.allocationId}`,
      `--start-epoch=${startEpoch}`,
      input.pieceCid,
      input.pieceCarPath
    ],
    context.boostRoot
  );

  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  return result.status === 0 && !/(^Error:|API not running|could not get API info)/m.test(`${result.stdout}\n${result.stderr}`);
}

export function currentLotusEpoch(context: ScenarioContext): number {
  return Number(runRequired("docker", ["exec", "lotus", "lotus", "chain", "head", "--height"], context.boostRoot).trim());
}

export function filecoinAddressFromEvmStat(output: string): string | undefined {
  return output.match(/Filecoin address:\s+(\S+)/)?.[1];
}

export function assertDirectImportSealingWindowIsSafe(window: DirectImportSealingWindow): void {
  const maxBuffer = Math.max(window.boostStartEpochSealingBuffer, window.minerStartEpochSealingBuffer);
  if (maxBuffer >= window.startEpochOffset) {
    throw new Error(
      `Unsafe direct import sealing window: Boost StartEpochSealingBuffer=${window.boostStartEpochSealingBuffer}, ` +
      `miner StartEpochSealingBuffer=${window.minerStartEpochSealingBuffer}, ` +
      `DIRECT_IMPORT_START_EPOCH_OFFSET=${window.startEpochOffset}. ` +
      "Run `just porep-v2-e2e-prepare-devnet` before live scenarios."
    );
  }
}

function readDirectImportSealingWindow(context: ScenarioContext, startEpochOffset: number): DirectImportSealingWindow {
  return {
    startEpochOffset,
    boostStartEpochSealingBuffer: requireTomlNumber(readContainerFile(context, "boost", BOOST_CONFIG), "StartEpochSealingBuffer"),
    minerStartEpochSealingBuffer: requireTomlNumber(readContainerFile(context, "lotus-miner", MINER_CONFIG), "StartEpochSealingBuffer")
  };
}

function readContainerFile(context: ScenarioContext, container: string, path: string): string {
  return dockerExec(context, container, ["bash", "-lc", `cat ${path}`]);
}

type TomlRequirement = {
  section: string;
  key: string;
  value: string;
};

function setTomlValue(context: ScenarioContext, container: string, path: string, requirement: TomlRequirement): void {
  const script = [
    "set -e",
    `file=${shellQuote(path)}`,
    `section=${shellQuote(requirement.section)}`,
    `key=${shellQuote(requirement.key)}`,
    `value=${shellQuote(requirement.value)}`,
    'if grep -q "^[[:space:]]*#\\?[[:space:]]*${key}[[:space:]]*=" "$file"; then',
    '  sed -i "s|^[[:space:]]*#\\?[[:space:]]*${key}[[:space:]]*=.*|  ${key} = ${value}|" "$file"',
    "else",
    '  sed -i "/^\\[${section}\\]/a\\  ${key} = ${value}" "$file"',
    "fi"
  ].join("\n");

  dockerExec(context, container, ["bash", "-lc", script]);
}

function tomlValue(config: string, key: string): string | undefined {
  let commented: string | undefined;
  for (const line of config.split(/\r?\n/)) {
    const match = line.match(new RegExp(`^\\s*(#?)\\s*${escapeRegExp(key)}\\s*=\\s*(.+?)\\s*$`));
    if (!match) continue;
    const [, comment, rawValue] = match;
    const value = normalizeTomlValue(rawValue ?? "");
    if (comment === "") return value;
    commented ??= value;
  }
  return commented;
}

function requireTomlNumber(config: string, key: string): number {
  const value = tomlValue(config, key);
  if (value === undefined) throw new Error(`missing ${key} in devnet config`);
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) throw new Error(`${key} is not numeric: ${value}`);
  return parsed;
}

function normalizeTomlValue(value: string): string {
  return value.trim().replace(/^"|"$/g, "");
}

async function waitForContainerHealthy(context: ScenarioContext, container: string): Promise<void> {
  for (let attempt = 1; attempt <= 30; attempt++) {
    const status = run("docker", ["inspect", container, "--format", "{{.State.Health.Status}}"], context.boostRoot).stdout.trim();
    if (status === "healthy") return;
    await sleep(5_000);
  }

  const logs = run("docker", ["logs", "--tail", "80", container], context.boostRoot);
  throw new Error(`${container} did not become healthy\n${logs.stderr || logs.stdout}`);
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
