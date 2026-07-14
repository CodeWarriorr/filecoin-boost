import { existsSync, readFileSync } from "node:fs";

export type ContractCheck = {
  address: string;
  code: "present" | "missing";
  deploymentRequired: boolean;
  deploymentAddress?: string;
  matchesDeployment?: boolean;
  abiPath?: string;
  abiPresent?: boolean;
};

export type DeploymentRecordStatus = "valid" | "missing" | "malformed";
export type DeploymentChainId = number | "missing" | "malformed";

export type DeploymentRecord = {
  status: DeploymentRecordStatus;
  entries: Record<string, unknown>;
  chainId: DeploymentChainId;
};

export type PreflightFacts = {
  boostBranch: string;
  boostCommit: string;
  porepSourceDir: string;
  porepBranch: string;
  porepCommit: string;
  expectedPorepCommit: string;
  porepDirty: string[];
  deploymentRecordPath: string;
  deploymentRecordStatus: DeploymentRecordStatus;
  deploymentRecordChainId: DeploymentChainId;
  devnetStatus: string;
  chainId: number | undefined;
  expectedChainId: number;
  binaries: Record<string, boolean>;
  requiredEnv: Record<string, "[set]" | "[missing]">;
  contracts: Record<string, ContractCheck>;
  runDir: string;
};

export function buildPreflightSummary(facts: PreflightFacts): string {
  const lines = [
    "PoRep Market V2 E2E preflight",
    `Boost: ${facts.boostBranch} @ ${facts.boostCommit}`,
    `PoRep: ${facts.porepBranch} @ ${facts.porepCommit}`,
    `Expected PoRep commit: ${facts.expectedPorepCommit}`,
    `PoRep source: ${facts.porepSourceDir}`,
    `PoRep dirty: ${facts.porepDirty.length > 0 ? facts.porepDirty.join("; ") : "clean"}`,
    `Deployment record: ${facts.deploymentRecordStatus} (${facts.deploymentRecordPath})`,
    `Deployment record chain ID: ${facts.deploymentRecordChainId}`,
    `Devnet: ${facts.devnetStatus}`,
    `Chain ID: ${facts.chainId ?? "unavailable"} (expected ${facts.expectedChainId})`,
    `Binaries: ${formatRecord(facts.binaries, (value) => (value ? "ok" : "missing"), ": ")}`,
    `Env: ${formatRecord(facts.requiredEnv, (value) => value)}`,
    `Contracts: ${formatContractChecks(facts.contracts)}`,
    `Run artifacts: ${facts.runDir}`
  ];

  return `${lines.join("\n")}\n`;
}

export function assertPreflightReady(facts: PreflightFacts): void {
  const failures: string[] = [];
  if (facts.chainId !== facts.expectedChainId) {
    failures.push(`chainId: expected ${facts.expectedChainId}, got ${facts.chainId ?? "unavailable"}`);
  }
  if (facts.porepCommit !== facts.expectedPorepCommit) {
    failures.push(`porepCommit: expected ${facts.expectedPorepCommit}, got ${facts.porepCommit}`);
  }
  if (facts.porepDirty.length > 0) {
    failures.push(`porepDirty: source-bearing local changes (${facts.porepDirty.join("; ")})`);
  }
  if (facts.deploymentRecordStatus !== "valid") {
    failures.push(`deploymentRecord: ${facts.deploymentRecordStatus}`);
  }
  if (facts.deploymentRecordChainId !== facts.expectedChainId) {
    failures.push(`deploymentRecord.chainId: expected ${facts.expectedChainId}, got ${facts.deploymentRecordChainId}`);
  }
  for (const [name, value] of Object.entries(facts.requiredEnv)) {
    if (value === "[missing]") failures.push(`requiredEnv.${name}: missing`);
  }
  for (const [name, present] of Object.entries(facts.binaries)) {
    if (!present) failures.push(`binaries.${name}: missing`);
  }
  if (facts.devnetStatus !== "available") failures.push(`devnetStatus: ${facts.devnetStatus}`);
  for (const [name, check] of Object.entries(facts.contracts)) {
    if (check.code === "missing") failures.push(`contracts.${name}.code: missing`);
    if (check.abiPresent === false) failures.push(`contracts.${name}.abi: missing`);
    if (check.deploymentRequired && check.deploymentAddress === undefined) {
      failures.push(`contracts.${name}.deploymentAddress: missing`);
    } else if (check.deploymentAddress !== undefined && check.matchesDeployment !== true) {
      failures.push(`contracts.${name}.deploymentAddress: mismatch`);
    }
  }
  if (failures.length > 0) throw new Error(`preflight failed:\n${failures.join("\n")}`);
}

export function assertExpectedChainId(chainId: number | undefined, expectedChainId: number): void {
  if (chainId !== expectedChainId) {
    throw new Error(`expected chain ID ${expectedChainId}, got ${chainId ?? "unavailable"}`);
  }
}

export function readDeploymentRecord(path: string): DeploymentRecord {
  if (!existsSync(path)) return { status: "missing", entries: {}, chainId: "missing" };
  try {
    const parsed: unknown = JSON.parse(readFileSync(path, "utf8"));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      return { status: "malformed", entries: {}, chainId: "malformed" };
    }
    const entries = parsed as Record<string, unknown>;
    return { status: "valid", entries, chainId: deploymentChainIdFor(entries) };
  } catch {
    return { status: "malformed", entries: {}, chainId: "malformed" };
  }
}

function deploymentChainIdFor(entries: Record<string, unknown>): DeploymentChainId {
  if (!("chainId" in entries)) return "missing";
  const value = entries.chainId;
  if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) return value;
  if (typeof value === "string" && /^(0|[1-9][0-9]*)$/.test(value)) {
    const parsed = Number(value);
    if (Number.isSafeInteger(parsed)) return parsed;
  }
  return "malformed";
}

export function filterPorepSourceChanges(statusLines: string[]): string[] {
  return statusLines.filter((line) => {
    const path = line.slice(3);
    const paths = path.split(" -> ");
    return !paths.every((candidate) => /^deployments\/devnet\/[^/]+\.json$/.test(candidate));
  });
}

function formatRecord<T>(record: Record<string, T>, format: (value: T) => string, separator = "="): string {
  return Object.entries(record)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}${separator}${format(value)}`)
    .join(", ");
}

function formatContractChecks(contracts: Record<string, ContractCheck>): string {
  return Object.entries(contracts)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([name, check]) => {
      const deployment = check.deploymentAddress === undefined
        ? (check.deploymentRequired ? ", deployment=missing" : "")
        : `, deployment=${check.matchesDeployment ? "match" : "mismatch"}`;
      const abi = check.abiPath === undefined ? "" : `, abi=${check.abiPresent ? "present" : "missing"}`;
      return `${name}(${check.code}${deployment}${abi})`;
    })
    .join(", ");
}
