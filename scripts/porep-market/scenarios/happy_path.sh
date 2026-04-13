#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/../setup/_common.sh"

STATE_FILE=${1:-"/tmp/porep-happy-path-$$.state"}
STATE_FILE=$(realpath "$STATE_FILE")
export STATE_FILE
echo "State: $STATE_FILE"

echo "============================================================"
echo "  HAPPY PATH: Full Deal Lifecycle"
echo "============================================================"

bash "$SETUP/06_prepare_operator.sh"
GENERATE_PIECE=1 bash "$SETUP/07_generate_piece.sh"

bash "$STEPS/07_propose_deal.sh" 0 0 86400000000 360;  state_require DEAL_ID
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

state_load
echo ""
echo "============================================================"
echo "  VERIFICATION"
echo "============================================================"
echo "Deal $DEAL_ID:     Completed"
echo "Validator:    $VALIDATOR"
echo "Rail ID:      $RAIL_ID"
echo "SP received:  $PAID_AMOUNT attoUSDC ($((PAID_AMOUNT / 1000000)) USDC)"
echo ""
echo "RESULT: Happy path verified end-to-end."
echo "  Proposed -> Accepted -> Validator -> Rail -> Allocated -> Claimed -> Settled -> Withdrawn"
echo "============================================================"
