#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/_common.sh"

STATE_FILE="/tmp/porep-happy-path-verified-$$.state"
export STATE_FILE
echo "State: $STATE_FILE"

echo "============================================================"
echo "  HAPPY PATH VERIFIED: Full Deal Lifecycle With Assertions"
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

state_load
state_require DEAL_ID VALIDATOR RAIL_ID DEPLOYER SP_WALLET

DEAL_VALIDATOR=$(get_deal_field "$DEAL_ID" 11)
DEAL_STATE_BEFORE_SETTLE=$(get_deal_field "$DEAL_ID" 12)
DEAL_RAIL_ID=$(get_deal_field "$DEAL_ID" 13)
RAIL_RATE=$(rail_payment_rate "$RAIL_ID")
RAIL_SETTLED_START=$(rail_settled_up_to "$RAIL_ID")

assert_eq "$(canon_addr "$DEAL_VALIDATOR")" "$(canon_addr "$VALIDATOR")" "deal validator mismatch"
assert_eq "$DEAL_RAIL_ID" "$RAIL_ID" "deal railId mismatch"
assert_eq "$DEAL_STATE_BEFORE_SETTLE" "2" "deal should be Completed before settlement"
assert_gt "$RAIL_RATE" 0 "rail payment rate should be positive after activation"

CLIENT_FP_BEFORE_SETTLE=$(fp_balance "$DEPLOYER")
SP_FP_BEFORE_SETTLE=$(fp_balance "$SP_WALLET")

bash "$STEPS/17_settle_rail.sh"

state_load
PAID_AMOUNT="${PAID_AMOUNT:?PAID_AMOUNT missing after settlement}"
RAIL_SETTLED_END=$(rail_settled_up_to "$RAIL_ID")
CLIENT_FP_AFTER_SETTLE=$(fp_balance "$DEPLOYER")
SP_FP_AFTER_SETTLE=$(fp_balance "$SP_WALLET")

CLIENT_DELTA=$((CLIENT_FP_AFTER_SETTLE - CLIENT_FP_BEFORE_SETTLE))
SP_DELTA=$((SP_FP_AFTER_SETTLE - SP_FP_BEFORE_SETTLE))
SETTLEMENT=$((-CLIENT_DELTA))
EXPECTED_FEE=$(((SETTLEMENT + 199) / 200))
ACTUAL_FEE=$((SETTLEMENT - SP_DELTA))

assert_gt "$PAID_AMOUNT" 0 "settlement should pay the SP"
assert_gt "$RAIL_SETTLED_END" "$RAIL_SETTLED_START" "rail settledUpTo should advance"
assert_eq "$SP_DELTA" "$PAID_AMOUNT" "SP FilecoinPay delta should equal PAID_AMOUNT"
assert_eq "$ACTUAL_FEE" "$EXPECTED_FEE" "protocol fee mismatch after settlement"

SP_ERC20_BEFORE_WITHDRAW=$(erc20_balance "$SP_WALLET")
bash "$STEPS/18_withdraw_payments.sh" "$PAID_AMOUNT"
SP_ERC20_AFTER_WITHDRAW=$(erc20_balance "$SP_WALLET")
SP_FP_AFTER_WITHDRAW=$(fp_balance "$SP_WALLET")
DEAL_STATE_AFTER_WITHDRAW=$(get_deal_field "$DEAL_ID" 12)

SP_ERC20_DELTA=$((SP_ERC20_AFTER_WITHDRAW - SP_ERC20_BEFORE_WITHDRAW))
SP_FP_WITHDRAW_DELTA=$((SP_FP_AFTER_WITHDRAW - SP_FP_AFTER_SETTLE))

assert_eq "$DEAL_STATE_AFTER_WITHDRAW" "2" "deal should remain Completed after withdraw"
assert_eq "$SP_ERC20_DELTA" "$PAID_AMOUNT" "SP ERC-20 balance delta should equal withdrawn amount"
assert_eq "$SP_FP_WITHDRAW_DELTA" "$((-PAID_AMOUNT))" "SP FilecoinPay balance should decrease by withdrawn amount"

echo ""
echo "============================================================"
echo "  VERIFICATION"
echo "============================================================"
echo "Deal ID:              $DEAL_ID"
echo "Deal state:           $DEAL_STATE_AFTER_WITHDRAW (Completed)"
echo "Validator:            $VALIDATOR"
echo "Rail ID:              $RAIL_ID"
echo "Rail rate:            $RAIL_RATE attoUSDC/epoch"
echo "Settled epochs:       $RAIL_SETTLED_START -> $RAIL_SETTLED_END"
echo "Client FP delta:      $CLIENT_DELTA"
echo "SP FP delta:          +$SP_DELTA"
echo "Protocol fee:         $ACTUAL_FEE"
echo "SP ERC-20 delta:      +$SP_ERC20_DELTA"
echo "SP FP withdraw delta: $SP_FP_WITHDRAW_DELTA"
echo ""
echo "RESULT: Verified happy path passed with explicit state and accounting assertions."
echo "============================================================"
