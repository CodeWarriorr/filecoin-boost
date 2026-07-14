import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { loadConfig, type E2EConfig } from "./config.js";
import {
  assertExpectedChainId,
  assertPreflightReady,
  buildPreflightSummary,
  filterPorepSourceChanges,
  readDeploymentRecord,
  type ContractCheck,
  type PreflightFacts
} from "./preflight.js";
import { createScenarioContext } from "./runtime.js";
import { resolveScenario } from "./scenarios/registry.js";
import { run, runRequired } from "./shell.js";

const scenario = process.argv[2] ?? "preflight";

try {
  const config = loadConfig({ cwd: process.cwd(), allowMissing: scenario === "preflight" });
  const runDir = createRunDir(config.runRoot);

  if (scenario === "preflight") {
    const facts = collectPreflightFacts(config, runDir);
    const summary = buildPreflightSummary(facts);
    writeFileSync(join(runDir, "summary.txt"), summary);
    writeFileSync(join(runDir, "summary.json"), `${JSON.stringify(facts, null, 2)}\n`);
    process.stdout.write(summary);
    assertPreflightReady(facts);
  } else {
    assertExpectedChainId(readChainId(config.rpcUrl), config.expectedChainId ?? 31415926);
    await resolveScenario(scenario)(createScenarioContext(config, runDir));
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}

function collectPreflightFacts(config: E2EConfig, runDir: string): PreflightFacts {
  const porepSourceDir = config.porepSourceDir;
  const scriptsRoot = resolve(config.cwd, "../..");
  const deploymentRecordPath = config.deploymentRecordPath ?? join(config.porepSourceDir, "deployments/devnet/latest.json");
  const deploymentRecord = readDeploymentRecord(deploymentRecordPath);
  const porepStatus = run("git", ["-C", porepSourceDir, "status", "--short", "--untracked-files=all"]);
  return {
    boostBranch: runRequired("git", ["rev-parse", "--abbrev-ref", "HEAD"], resolve(process.cwd(), "../../../..")),
    boostCommit: runRequired("git", ["rev-parse", "HEAD"], resolve(process.cwd(), "../../../..")),
    porepSourceDir,
    porepBranch: runRequired("git", ["-C", porepSourceDir, "rev-parse", "--abbrev-ref", "HEAD"]),
    porepCommit: runRequired("git", ["-C", porepSourceDir, "rev-parse", "HEAD"]),
    expectedPorepCommit: config.expectedPorepCommit ?? "803942a5f439e0a588da245727197ca22546bb1f",
    porepDirty: filterPorepSourceChanges(porepStatus.stdout.trim().split("\n").filter(Boolean)),
    deploymentRecordPath,
    deploymentRecordStatus: deploymentRecord.status,
    deploymentRecordChainId: deploymentRecord.chainId,
    devnetStatus: run("docker", ["exec", "lotus", "lotus", "chain", "head"]).status === 0 ? "available" : "unavailable",
    chainId: readChainId(config.rpcUrl),
    expectedChainId: config.expectedChainId ?? 31415926,
    binaries: Object.fromEntries(["forge", "cast", "docker", "node"].map((binary) => [binary, hasBinary(binary)])),
    requiredEnv: config.requiredEnv,
    contracts: collectContractChecks(config, scriptsRoot, deploymentRecord.entries),
    runDir
  };
}

function readChainId(rpcUrl: string): number | undefined {
  const result = run("cast", ["chain-id", "--rpc-url", rpcUrl]);
  const value = Number(result.stdout.trim());
  return result.status === 0 && Number.isSafeInteger(value) ? value : undefined;
}

function collectContractChecks(
  config: E2EConfig,
  scriptsRoot: string,
  deployments: Record<string, unknown>
): Record<string, ContractCheck> {
  const definitions: Array<[keyof E2EConfig["addresses"], string, boolean, string[]]> = [
    ["poRepMarket", "PoRepMarket", true, [join(config.porepSourceDir, "out/PoRepMarket.sol/PoRepMarket.json")]],
    ["spRegistry", "SPRegistry", true, [join(config.porepSourceDir, "out/SPRegistry.sol/SPRegistry.json")]],
    ["validatorFactory", "ValidatorFactory", true, [join(config.porepSourceDir, "out/ValidatorFactory.sol/ValidatorFactory.json")]],
    ["dataCapEvidenceAdapter", "DataCapEvidenceAdapter", true, [join(config.porepSourceDir, "out/DataCapEvidenceAdapter.sol/DataCapEvidenceAdapter.json")]],
    ["filecoinPay", "FilecoinPay", true, [join(scriptsRoot, "filecoin-pay/out/FilecoinPayV1.sol/FilecoinPayV1.json")]],
    ["sliOracle", "SLIOracle", true, [join(config.porepSourceDir, "out/SLIOracle.sol/SLIOracle.json")]],
    ["metaAllocator", "MetaAllocator", true, []],
    ["usdcToken", "USDC_TOKEN", false, [join(config.porepSourceDir, "out/MockUSDC.sol/MockUSDC.json"), join(scriptsRoot, "porep-market/out/MockUSDC.sol/MockUSDC.json")]]
  ];
  return Object.fromEntries(definitions.map(([key, deploymentName, deploymentRequired, abiPaths]) => {
    const address = config.addresses[key];
    const deploymentAddress = deploymentAddressFor(deployments[deploymentName]);
    const abiPath = abiPaths.find(existsSync);
    return [key, {
      address,
      code: hasCode(config.rpcUrl, address) ? "present" : "missing",
      deploymentRequired,
      ...(deploymentAddress === undefined ? {} : { deploymentAddress, matchesDeployment: equalAddress(address, deploymentAddress) }),
      ...(abiPaths.length === 0 ? {} : { abiPath: abiPath ?? abiPaths[0], abiPresent: abiPath !== undefined })
    } satisfies ContractCheck];
  }));
}

function hasCode(rpcUrl: string, address: string): boolean {
  const result = run("cast", ["code", "--rpc-url", rpcUrl, address]);
  return result.status === 0 && result.stdout.trim() !== "0x" && result.stdout.trim() !== "";
}

function deploymentAddressFor(value: unknown): string | undefined {
  if (typeof value === "string") return value;
  if (typeof value === "object" && value !== null && "proxy" in value && typeof value.proxy === "string") return value.proxy;
  return undefined;
}

function equalAddress(left: string, right: string): boolean {
  return left.toLowerCase() === right.toLowerCase();
}

function hasBinary(binary: string): boolean {
  return run("sh", ["-c", `command -v ${binary}`]).status === 0;
}

function createRunDir(root: string): string {
  const dir = join(root, new Date().toISOString().replace(/[:.]/g, "-"));
  mkdirSync(dir, { recursive: true });
  return dir;
}
