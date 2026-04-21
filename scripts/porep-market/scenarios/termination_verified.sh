#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/_common.sh"

STATE_FILE="/tmp/porep-termination-verified-$$.state"
export STATE_FILE
echo "State: $STATE_FILE"

echo "============================================================"
echo "  TERMINATION VERIFIED: End-to-End Termination Assertions"
echo "============================================================"

bash "$SETUP/06_prepare_operator.sh"
GENERATE_PIECE=1 bash "$SETUP/07_generate_piece.sh"

bash "$STEPS/07_propose_deal.sh" 0 0 2000000 360;  state_require DEAL_ID
bash "$STEPS/08_accept_deal.sh"
bash "$STEPS/10_deploy_validator.sh";               state_require VALIDATOR
bash "$STEPS/11_deposit_and_approve_operator.sh" 100
bash "$STEPS/12_create_rail.sh";                    state_require RAIL_ID
bash "$STEPS/13_make_allocation.sh"
bash "$SETUP/08_ensure_boost.sh"
bash "$STEPS/14_import_piece.sh"
CLAIM_MAX_ATTEMPTS=60 bash "$STEPS/16_wait_for_claim.sh"

END_EPOCH_OFFSET=500 MIN_INTERVAL=1 SETTLE_WAIT=5 \
    bash "$STEPS/20_activate_payment.sh"

state_load
state_require DEAL_ID VALIDATOR RAIL_ID DEPLOYER SP_WALLET

DEAL_VALIDATOR=$(get_deal_field "$DEAL_ID" 11)
DEAL_STATE_BEFORE=$(get_deal_field "$DEAL_ID" 12)
DEAL_RAIL_ID=$(get_deal_field "$DEAL_ID" 13)
RAIL_RATE=$(rail_payment_rate "$RAIL_ID")
LOCKUP_PERIOD=86400
FULL_DURATION_MAX=$((RAIL_RATE * 500))

assert_eq "$(canon_addr "$DEAL_VALIDATOR")" "$(canon_addr "$VALIDATOR")" "deal validator mismatch before termination"
assert_eq "$DEAL_STATE_BEFORE" "2" "deal should be Completed before termination"
assert_eq "$DEAL_RAIL_ID" "$RAIL_ID" "deal railId mismatch before termination"
assert_gt "$RAIL_RATE" 0 "rail payment rate should be positive before termination"

echo "Rail rate:         $RAIL_RATE units/epoch"
echo "Full duration max: $FULL_DURATION_MAX units (rate × 500 epochs)"

echo "Waiting 60s to accumulate pre-termination payment..."
sleep 60

bash "$STEPS/17_settle_rail.sh"

state_load
PAID_PARTIAL="${PAID_AMOUNT:?missing PAID_AMOUNT after partial settlement}"
LAST_SETTLED_BEFORE_TERM=$(rail_settled_up_to "$RAIL_ID")
END_EPOCH_BEFORE=$(rail_end_epoch "$RAIL_ID")

echo "Partial payment:  $PAID_PARTIAL units"
echo "settledUpTo:      $LAST_SETTLED_BEFORE_TERM"
echo "endEpoch before:  $END_EPOCH_BEFORE"

bash "$STEPS/19_rail_termination.sh" "$VALIDATOR" "$RAIL_ID"

DEAL_STATE_AFTER_TERM=$(get_deal_field "$DEAL_ID" 12)
TERM_END_EPOCH=$(rail_end_epoch "$RAIL_ID")
EXPECTED_END_EPOCH=$((LAST_SETTLED_BEFORE_TERM + LOCKUP_PERIOD))
FORMULA_DELTA=$((TERM_END_EPOCH - EXPECTED_END_EPOCH))

assert_eq "$DEAL_STATE_AFTER_TERM" "4" "deal should be Terminated after termination"
assert_gt "$TERM_END_EPOCH" 0 "endEpoch should be set after termination"
[ "$FORMULA_DELTA" -ge -5 ] && [ "$FORMULA_DELTA" -le 5 ] || \
    fail "termination endEpoch formula mismatch (actual=$TERM_END_EPOCH expected=$EXPECTED_END_EPOCH delta=$FORMULA_DELTA)"

echo "endEpoch after:   $TERM_END_EPOCH"
echo "Expected formula: $EXPECTED_END_EPOCH"

SP_FP_BEFORE_POST_TERM=$(fp_balance "$SP_WALLET")
POST_TERM_TARGET=$(cast block-number --rpc-url "$RPC_URL")
POST_TERM_TX=$(send_tx_hash "$FILECOIN_PAY" "settleRail(uint256,uint256)" "$RAIL_ID" "$POST_TERM_TARGET")
wait_for_tx "$POST_TERM_TX"
SP_FP_AFTER_POST_TERM=$(fp_balance "$SP_WALLET")
POST_TERM_PAID=$((SP_FP_AFTER_POST_TERM - SP_FP_BEFORE_POST_TERM))
TOTAL_PAID=$((PAID_PARTIAL + POST_TERM_PAID))
LAST_SETTLED_AFTER_TERM=$(rail_settled_up_to "$RAIL_ID")

assert_ge "$POST_TERM_PAID" 0 "post-termination settlement delta should not be negative"
assert_gt "$TOTAL_PAID" 0 "total paid after termination flow should be positive"
[ "$TOTAL_PAID" -lt "$FULL_DURATION_MAX" ] || \
    fail "termination flow paid full pre-termination duration or more (total=$TOTAL_PAID cap=$FULL_DURATION_MAX)"

# Re-settle to the exact same epoch to prove no double payment at a fixed boundary.
SP_FP_BEFORE_NOOP=$(fp_balance "$SP_WALLET")
NOOP_TX=$(send_tx_hash "$FILECOIN_PAY" "settleRail(uint256,uint256)" "$RAIL_ID" "$LAST_SETTLED_AFTER_TERM")
wait_for_tx "$NOOP_TX"
SP_FP_AFTER_NOOP=$(fp_balance "$SP_WALLET")
NOOP_PAID=$((SP_FP_AFTER_NOOP - SP_FP_BEFORE_NOOP))
assert_eq "$NOOP_PAID" "0" "settling again to the same epoch should not pay twice"

SP_ERC20_BEFORE_WITHDRAW=$(erc20_balance "$SP_WALLET")
bash "$STEPS/18_withdraw_payments.sh" "$TOTAL_PAID"
SP_ERC20_AFTER_WITHDRAW=$(erc20_balance "$SP_WALLET")
SP_FP_AFTER_WITHDRAW=$(fp_balance "$SP_WALLET")
DEAL_STATE_FINAL=$(get_deal_field "$DEAL_ID" 12)

SP_ERC20_DELTA=$((SP_ERC20_AFTER_WITHDRAW - SP_ERC20_BEFORE_WITHDRAW))
SP_FP_WITHDRAW_DELTA=$((SP_FP_AFTER_WITHDRAW - SP_FP_AFTER_NOOP))

assert_eq "$DEAL_STATE_FINAL" "4" "deal should remain Terminated after withdraw"
assert_eq "$SP_ERC20_DELTA" "$TOTAL_PAID" "SP ERC-20 delta should equal total withdrawn amount"
assert_eq "$SP_FP_WITHDRAW_DELTA" "$((-TOTAL_PAID))" "SP FilecoinPay balance should decrease by withdrawn amount"

echo ""
echo "============================================================"
echo "  VERIFICATION"
echo "============================================================"
echo "Deal ID:                    $DEAL_ID"
echo "Deal state after terminate: $DEAL_STATE_AFTER_TERM (Terminated)"
echo "Deal state final:           $DEAL_STATE_FINAL (Terminated)"
echo "Validator:                  $VALIDATOR"
echo "Rail ID:                    $RAIL_ID"
echo "Rail rate:                  $RAIL_RATE attoUSDC/epoch"
echo "settledUpTo before term:    $LAST_SETTLED_BEFORE_TERM"
echo "settledUpTo after term:     $LAST_SETTLED_AFTER_TERM"
echo "endEpoch before term:       $END_EPOCH_BEFORE"
echo "endEpoch after  term:       $TERM_END_EPOCH"
echo "Expected endEpoch formula:  $EXPECTED_END_EPOCH"
echo "Partial paid:               $PAID_PARTIAL"
echo "Post-term paid:             $POST_TERM_PAID"
echo "No-op settle paid:          $NOOP_PAID"
echo "Total paid:                 $TOTAL_PAID"
echo "SP ERC-20 delta:            +$SP_ERC20_DELTA"
echo "SP FP withdraw delta:       $SP_FP_WITHDRAW_DELTA"
echo ""
echo "RESULT: Verified termination passed with state, payment, and no-double-pay assertions."
echo "============================================================"
