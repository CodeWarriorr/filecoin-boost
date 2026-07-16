#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/_common.sh"

STATE_FILE=${1:-"/tmp/porep-v2-full-available-$$.state"}
STATE_DIR="$(cd "$(dirname "$STATE_FILE")" && pwd)"
STATE_FILE="$STATE_DIR/$(basename "$STATE_FILE")"
export STATE_FILE

echo "State: $STATE_FILE"

bash "$SETUP/04_register_provider_and_offer.sh"
bash "$STEPS/07_propose_deal.sh"
bash "$STEPS/10_deploy_validator.sh"
bash "$STEPS/11_deposit_and_approve_operator.sh" "$(default_v2_deposit_amount)"
bash "$STEPS/12_create_rail.sh"
bash "$SETUP/07_generate_piece.sh"
bash "$STEPS/13_submit_datacap_batch.sh"
bash "$SETUP/08_ensure_boost.sh"
bash "$STEPS/14_import_piece.sh"
bash "$STEPS/16_wait_for_claim.sh"
bash "$STEPS/17_finish_datacap_posting.sh"
bash "$STEPS/18_submit_evidence_batch.sh"
bash "$STEPS/19_activate_evidence.sh"
bash "$STEPS/20_set_sli_attestation.sh"
bash "$STEPS/20_set_min_settlement_epochs.sh"
bash "$STEPS/21_wait_settlement_window.sh"
bash "$STEPS/22_refresh_evidence_status.sh"
bash "$STEPS/23_settle_rail.sh"

state_require DEAL_ID VALIDATOR RAIL_ID ALLOC_ID CLAIM_IDS_CSV COMMITTED_BYTES PAYMENT_RATE SLI_LAST_UPDATE EVIDENCE_ACTIVE_COVERED_BYTES PAID_AMOUNT

echo "RESULT: V2 full available flow activated, attested SLI at $SLI_LAST_UPDATE, refreshed evidence, and settled deal $DEAL_ID, validator $VALIDATOR, rail $RAIL_ID, allocation $ALLOC_ID, active evidence bytes $EVIDENCE_ACTIVE_COVERED_BYTES, paid $PAID_AMOUNT."
