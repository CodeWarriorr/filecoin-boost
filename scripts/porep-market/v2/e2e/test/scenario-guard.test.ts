import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

test("TypeScript scenarios do not wrap state-changing bash steps", () => {
  const sourceDir = join(import.meta.dirname, "../src");
  const sources = readdirSync(sourceDir, { recursive: true, encoding: "utf8" })
    .filter((name) => name.endsWith(".ts"))
    .map((name) => ({ name, source: readFileSync(join(sourceDir, name), "utf8") }));
  const forbidden = [
    new RegExp("script" + "Step\\("),
    new RegExp("command:\\s*\"" + "bash" + "\""),
    new RegExp("v2/" + "steps/"),
    new RegExp("v2/" + "setup/0[478]_")
  ];

  for (const { name, source } of sources) {
    for (const pattern of forbidden) {
      assert.doesNotMatch(source, pattern, `${name} must not delegate scenario state changes to Bash`);
    }
  }
});

test("deploy-readiness just target performs explicit funding setup before live scenarios", () => {
  const justfile = readFileSync(join(import.meta.dirname, "../../../../../justfile"), "utf8");
  const suiteMatch = /^porep-v2-e2e-deploy-readiness:\n(?<body>(?:    .+\n)+)/m.exec(justfile);
  assert.ok(suiteMatch?.groups?.body, "missing porep-v2-e2e-deploy-readiness target");

  const body = suiteMatch.groups.body;
  const devnetIndex = body.indexOf("porep-v2-e2e-prepare-devnet");
  const fundingIndex = body.indexOf("porep-v2-e2e-ensure-suite-funding");
  const firstScenarioIndex = body.indexOf("porep-v2-e2e-evidence-no-claim-activation-guard");
  assert.notEqual(devnetIndex, -1, "deploy-readiness target must prepare fast-sealing devnet");
  assert.notEqual(fundingIndex, -1, "deploy-readiness target must call explicit funding setup");
  assert.notEqual(firstScenarioIndex, -1, "deploy-readiness target must run live guard scenarios");
  assert.ok(devnetIndex < fundingIndex, "devnet preparation must run before funding");
  assert.ok(fundingIndex < firstScenarioIndex, "funding setup must run before live guard scenarios");
});

test("local-devnet P0/P1 just target runs explicit setup then selected TypeScript scenarios", () => {
  const justfile = readFileSync(join(import.meta.dirname, "../../../../../justfile"), "utf8");
  const suiteMatch = /^porep-v2-e2e-local-devnet-p0-p1:\n(?<body>(?:    .+\n)+)/m.exec(justfile);
  assert.ok(suiteMatch?.groups?.body, "missing porep-v2-e2e-local-devnet-p0-p1 target");

  const body = suiteMatch.groups.body;
  const expectedOrder = [
    "porep-v2-e2e-preflight",
    "porep-v2-e2e-prepare-devnet",
    "porep-v2-e2e-ensure-suite-funding",
    "porep-v2-e2e-multi-claim-evidence-batches",
    "porep-v2-e2e-shared-client-multi-rail-settlement",
    "porep-v2-e2e-evidence-authority-guards",
    "porep-v2-e2e-actor-token-guards"
  ];

  let lastIndex = -1;
  for (const target of expectedOrder) {
    const index = body.indexOf(target);
    assert.notEqual(index, -1, `aggregate target must run ${target}`);
    assert.ok(index > lastIndex, `${target} must run after the previous aggregate step`);
    lastIndex = index;
  }
});

test("individual live TypeScript scenarios prepare fast-sealing devnet before running", () => {
  const justfile = readFileSync(join(import.meta.dirname, "../../../../../justfile"), "utf8");
  const targets = [
    "porep-v2-e2e-basic-activation",
    "porep-v2-e2e-full-available",
    "porep-v2-e2e-evidence-no-claim-activation-guard",
    "porep-v2-e2e-activation-lifecycle-guards",
    "porep-v2-e2e-settlement-guards",
    "porep-v2-e2e-access-control-guards",
    "porep-v2-e2e-multi-claim-evidence-batches",
    "porep-v2-e2e-shared-client-multi-rail-settlement",
    "porep-v2-e2e-evidence-authority-guards",
    "porep-v2-e2e-actor-token-guards"
  ];

  for (const target of targets) {
    const match = new RegExp(`^${target}:\\n(?<body>(?:    .+\\n)+)`, "m").exec(justfile);
    assert.ok(match?.groups?.body, `missing ${target} target`);
    assert.match(match.groups.body, /just porep-v2-e2e-prepare-devnet/, `${target} must prepare devnet`);
  }
});

test("prepare-devnet just target is implemented by the TypeScript harness", () => {
  const justfile = readFileSync(join(import.meta.dirname, "../../../../../justfile"), "utf8");
  const match = /^porep-v2-e2e-prepare-devnet:\n(?<body>(?:    .+\n)+)/m.exec(justfile);
  assert.ok(match?.groups?.body, "missing porep-v2-e2e-prepare-devnet target");
  assert.match(match.groups.body, /npm --prefix \{\{scripts\}\}\/v2\/e2e run scenario -- prepare-devnet/);
  assert.doesNotMatch(match.groups.body, /bash .*08_ensure_boost\.sh/);
});

test("public full happy path includes fast-sealing preparation", () => {
  const justfile = readFileSync(join(import.meta.dirname, "../../../../../justfile"), "utf8");
  const match = /^porep-v2-full-happy-path:\n(?<body>(?:    .+\n)+)/m.exec(justfile);
  assert.ok(match?.groups?.body, "missing porep-v2-full-happy-path target");
  assert.match(match.groups.body, /just porep-v2-e2e-full-available/);
});

test("versioned V2 devnet lifecycle orders setup and smoke checks", () => {
  const justfile = readFileSync(join(import.meta.dirname, "../../../../../justfile"), "utf8");
  const match = /^porep-v2-devnet-up:\n(?<body>(?:    .+\n)+)/m.exec(justfile);
  assert.ok(match?.groups?.body, "missing porep-v2-devnet-up target");

  const body = match.groups.body;
  const expectedOrder = [
    "porep-v2-e2e-install",
    "make clean docker/all",
    "make devnet/up",
    "porep-v2-deploy",
    "porep-v2-e2e-ensure-suite-funding",
    "porep-v2-devnet-check",
    "porep-v2-e2e-proposal-smoke",
    "porep-v2-e2e-validator-rail-smoke"
  ];

  let lastIndex = -1;
  for (const step of expectedOrder) {
    const index = body.indexOf(step);
    assert.notEqual(index, -1, `porep-v2-devnet-up must run ${step}`);
    assert.ok(index > lastIndex, `${step} must run after the previous lifecycle step`);
    lastIndex = index;
  }
});
