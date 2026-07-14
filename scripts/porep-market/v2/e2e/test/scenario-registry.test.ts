import test from "node:test";
import assert from "node:assert/strict";
import { scenarioNames, resolveScenario } from "../src/scenarios/registry.js";

test("scenario registry exposes every supported CLI scenario", () => {
  assert.deepEqual(scenarioNames, [
    "access-control-guards",
    "activation-lifecycle-guards",
    "actor-token-guards",
    "basic-activation",
    "evidence-authority-guards",
    "evidence-no-claim-activation-guard",
    "full-available",
    "multi-claim-evidence-batches",
    "negative-activation",
    "prepare-devnet",
    "proposal-smoke",
    "settlement-guards",
    "shared-client-multi-rail-settlement",
    "validator-rail-smoke"
  ]);
});

test("scenario registry rejects unknown names instead of silently aliasing them", () => {
  assert.throws(() => resolveScenario("activation-only"), /unknown scenario: activation-only/);
});
