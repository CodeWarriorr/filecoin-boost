#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/../setup/_common.sh"

STATE_FILE="/tmp/early-termination-path-$$.state"
export STATE_FILE
echo "State: $STATE_FILE"

echo "============================================================"
echo "  TERMINATION PATH: Full Deal Lifecycle with early termination"
echo "============================================================"

bash "$SETUP/06_prepare_operator.sh"
GENERATE_PIECE=1 bash "$SETUP/07_generate_piece.sh"

bash "$STEPS/07_propose_deal.sh" 0 0 86400 360;        state_require DEAL_ID
bash "$STEPS/08_accept_deal.sh"
bash "$STEPS/10_deploy_validator.sh";                   state_require VALIDATOR
bash "$STEPS/11_deposit_and_approve_operator.sh" 864000
bash "$STEPS/12_create_rail.sh";                        state_require RAIL_ID
bash "$STEPS/13_make_allocation.sh"
bash "$SETUP/08_ensure_boost.sh"
bash "$STEPS/14_import_piece.sh"
bash "$STEPS/16_wait_for_claim.sh"
bash "$STEPS/20_activate_payment.sh"
bash "$STEPS/17_settle_rail.sh"
bash "$STEPS/18_withdraw_payments.sh"
bash "$STEPS/19a_set_lockup_period.sh"
bash "$STEPS/19_rail_termination.sh"
bash "$STEPS/21_settle_rail_after_termination.sh";

state_load
echo ""
echo "============================================================"
echo "  VERIFICATION"
echo "============================================================"
echo "Deal ID:                $DEAL_ID"
echo "Validator:              $VALIDATOR"
echo "Rail ID:                $RAIL_ID"
echo "Termination block:      $TERMINATION_BLOCK"
echo "Termination end epoch:  $TERMINATION_END_EPOCH"
echo ""
echo "Pre-term settlement:    $PAID_AMOUNT attoUSDC"
echo "Lockup window payment:  $PAID_AMOUNT_AFTER_TERMINATION attoUSDC"
echo "Extra settle delta:     $EXTRA_SETTLE_DELTA attoUSDC (expected 0)"
echo ""
echo "RESULT: Termination rail scenario verified end-to-end."
echo "  -> Settled (pre-term) -> Terminated -> Settled (up to endEpoch) -> Finalized"
echo "  -> Extra settle reverted (RailInactiveOrSettled) -> Extra delta = 0"
echo "============================================================"

