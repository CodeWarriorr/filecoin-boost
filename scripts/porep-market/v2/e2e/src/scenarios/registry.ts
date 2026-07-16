import type { ScenarioContext } from "../runtime.js";
import { prepareFastSealingDevnet } from "../devnet/boost.js";
import { runAccessControlGuards } from "./accessControlGuards.js";
import { runActivationLifecycleGuards } from "./activationLifecycleGuards.js";
import { runActorTokenGuards } from "./actorTokenGuards.js";
import { runBasicActivationFlow } from "./basicActivationFlow.js";
import { runEvidenceAuthorityGuards } from "./evidenceAuthorityGuards.js";
import { runEvidenceNoClaimActivationGuard } from "./evidenceNoClaimActivationGuard.js";
import { runFullAvailableFlow } from "./fullAvailableFlow.js";
import { runMultiClaimEvidenceBatches } from "./multiClaimEvidenceBatches.js";
import { runNegativeActivationBeforeEvidence } from "./negativeActivationFlow.js";
import { runSettlementGuards } from "./settlementGuards.js";
import { runSharedClientMultiRailSettlement } from "./sharedClientMultiRailSettlement.js";
import { runProposalSmoke, runValidatorRailSmoke } from "./smokeFlows.js";

type Scenario = (context: ScenarioContext) => Promise<void>;

const scenarios: Record<string, Scenario> = {
  "access-control-guards": runAccessControlGuards,
  "activation-lifecycle-guards": runActivationLifecycleGuards,
  "actor-token-guards": runActorTokenGuards,
  "basic-activation": runBasicActivationFlow,
  "evidence-authority-guards": runEvidenceAuthorityGuards,
  "evidence-no-claim-activation-guard": runEvidenceNoClaimActivationGuard,
  "full-available": runFullAvailableFlow,
  "multi-claim-evidence-batches": runMultiClaimEvidenceBatches,
  "negative-activation": runNegativeActivationBeforeEvidence,
  "prepare-devnet": prepareFastSealingDevnet,
  "proposal-smoke": runProposalSmoke,
  "settlement-guards": runSettlementGuards,
  "shared-client-multi-rail-settlement": runSharedClientMultiRailSettlement,
  "validator-rail-smoke": runValidatorRailSmoke
};

export const scenarioNames = Object.keys(scenarios).sort();

export function resolveScenario(name: string): Scenario {
  const scenario = scenarios[name];
  if (!scenario) throw new Error(`unknown scenario: ${name}`);
  return scenario;
}
