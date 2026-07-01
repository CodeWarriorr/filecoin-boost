#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/_common.sh"

STATE_FILE="/tmp/porep-multiple-pieces-$$.state"
export STATE_FILE
echo "State: $STATE_FILE"

echo "============================================================"
echo "  MULTIPLE PIECES VERIFIED: one deal, many allocations"
echo "============================================================"

PIECE_COUNT="${PIECE_COUNT:-3}"
PRICE_TOKENS="${PRICE_TOKENS:-2000000}"
DURATION_DAYS="${DURATION_DAYS:-360}"

join_by() {
    local delimiter="$1"
    shift
    local first=1
    for item in "$@"; do
        if [ "$first" -eq 1 ]; then
            printf '%s' "$item"
            first=0
        else
            printf '%s%s' "$delimiter" "$item"
        fi
    done
}

[ "${SKIP_SETUP:-}" = "1" ] || bash "$SETUP/06_prepare_operator.sh"
if [ "${SKIP_SETUP:-}" = "1" ]; then
    state_set DEPLOYER "$DEPLOYER"
    state_set SP_WALLET "$SP_WALLET"
    state_set MINER_ID "${MINER_ID:-1000}"
fi

declare -a MULTI_PIECE_CIDS
declare -a MULTI_PIECE_CID_HEXES
declare -a MULTI_PIECE_SIZES
declare -a MULTI_PIECE_CAR_PATHS

for i in $(seq 1 "$PIECE_COUNT"); do
    GENERATE_PIECE=1 bash "$SETUP/07_generate_piece.sh"
    state_load
    state_require PIECE_CID PIECE_CID_HEX PIECE_SIZE PIECE_CAR_PATH
    MULTI_PIECE_CIDS+=("$PIECE_CID")
    MULTI_PIECE_CID_HEXES+=("$PIECE_CID_HEX")
    MULTI_PIECE_SIZES+=("$PIECE_SIZE")
    MULTI_PIECE_CAR_PATHS+=("$PIECE_CAR_PATH")
    echo "Prepared piece $i/$PIECE_COUNT: $PIECE_CID"
done

PIECE_CID_HEXES_JOINED=$(join_by '|' "${MULTI_PIECE_CID_HEXES[@]}")
PIECE_SIZES_JOINED=$(join_by '|' "${MULTI_PIECE_SIZES[@]}")

state_set PIECE_CID_HEXES "$PIECE_CID_HEXES_JOINED"
state_set PIECE_SIZES "$PIECE_SIZES_JOINED"

bash "$STEPS/07_propose_deal.sh" 0 0 "$PRICE_TOKENS" "$DURATION_DAYS"; state_require DEAL_ID
bash "$STEPS/08_accept_deal.sh"
bash "$STEPS/10_deploy_validator.sh"; state_require VALIDATOR
bash "$STEPS/11_deposit_and_approve_operator.sh" 1000
bash "$STEPS/12_create_rail.sh"; state_require RAIL_ID
bash "$STEPS/13_make_allocations.sh"
[ "${SKIP_SETUP:-}" = "1" ] || bash "$SETUP/08_ensure_boost.sh"

state_load
state_require ALLOC_IDS_CSV ALLOC_COUNT DEAL_ID VALIDATOR RAIL_ID DEPLOYER SP_WALLET CLIENT_CONTRACT

IFS=',' read -r -a ALLOC_IDS <<< "$ALLOC_IDS_CSV"
[ "${#ALLOC_IDS[@]}" -eq "$PIECE_COUNT" ] || fail "expected $PIECE_COUNT allocation IDs, got ${#ALLOC_IDS[@]}"

for idx in "${!ALLOC_IDS[@]}"; do
    alloc_id="${ALLOC_IDS[$idx]}"
    piece_cid="${MULTI_PIECE_CIDS[$idx]}"
    piece_car_path="${MULTI_PIECE_CAR_PATHS[$idx]}"

    state_set ALLOC_ID "$alloc_id"
    state_set PIECE_CID "$piece_cid"
    state_set PIECE_CAR_PATH "$piece_car_path"

    bash "$STEPS/14_import_piece.sh"
done

for alloc_id in "${ALLOC_IDS[@]}"; do
    state_set ALLOC_ID "$alloc_id"
    CLAIM_MAX_ATTEMPTS="${CLAIM_MAX_ATTEMPTS:-900}" bash "$STEPS/16_wait_for_claim.sh"
done

END_EPOCH_OFFSET=500 MIN_INTERVAL=1 SETTLE_WAIT=5 \
    bash "$STEPS/20_activate_payment.sh"

state_load
state_require DEAL_ID VALIDATOR RAIL_ID DEPLOYER SP_WALLET

DEAL_VALIDATOR=$(get_deal_field "$DEAL_ID" 11)
DEAL_STATE_BEFORE_SETTLE=$(get_deal_field "$DEAL_ID" 12)
DEAL_RAIL_ID=$(get_deal_field "$DEAL_ID" 13)
ACTIVE_RAIL_RATE=$(rail_payment_rate "$RAIL_ID")
RAIL_SETTLED_START=$(rail_settled_up_to "$RAIL_ID")
EXPECTED_RATE=$((PRICE_TOKENS * PIECE_COUNT / 86400))

assert_eq "$(canon_addr "$DEAL_VALIDATOR")" "$(canon_addr "$VALIDATOR")" "deal validator mismatch"
assert_eq "$DEAL_RAIL_ID" "$RAIL_ID" "deal railId mismatch"
assert_eq "$DEAL_STATE_BEFORE_SETTLE" "2" "deal should be Completed before settlement"
assert_eq "$ACTIVE_RAIL_RATE" "$EXPECTED_RATE" "rail rate should scale with allocation count"

CLIENT_FP_BEFORE_SETTLE=$(fp_balance "$DEPLOYER")
SP_FP_BEFORE_SETTLE=$(fp_balance "$SP_WALLET")

sleep 60

bash "$STEPS/17_settle_rail.sh"

state_load
PAID_AMOUNT="${PAID_AMOUNT:?PAID_AMOUNT missing after settlement}"
RAIL_SETTLED_END=$(rail_settled_up_to "$RAIL_ID")
CLIENT_FP_AFTER_SETTLE=$(fp_balance "$DEPLOYER")
SP_FP_AFTER_SETTLE=$(fp_balance "$SP_WALLET")

CLIENT_DELTA=$((CLIENT_FP_AFTER_SETTLE - CLIENT_FP_BEFORE_SETTLE))
SP_DELTA=$((SP_FP_AFTER_SETTLE - SP_FP_BEFORE_SETTLE))
SETTLEMENT=$((-CLIENT_DELTA))
EPOCHS_ELAPSED=$((RAIL_SETTLED_END - RAIL_SETTLED_START))
EXPECTED_GROSS=$((ACTIVE_RAIL_RATE * EPOCHS_ELAPSED))
EXPECTED_FEE=$(((SETTLEMENT + 199) / 200))
ACTUAL_FEE=$((SETTLEMENT - SP_DELTA))

assert_gt "$PAID_AMOUNT" 0 "settlement should pay the SP"
assert_gt "$RAIL_SETTLED_END" "$RAIL_SETTLED_START" "rail settledUpTo should advance"
assert_eq "$SP_DELTA" "$PAID_AMOUNT" "SP FilecoinPay delta should equal PAID_AMOUNT"
assert_eq "$ACTUAL_FEE" "$EXPECTED_FEE" "protocol fee mismatch after settlement"
[ "$SETTLEMENT" -ge "$((EXPECTED_GROSS - ACTIVE_RAIL_RATE))" ] || fail "gross settlement under expected range (gross=$SETTLEMENT expected>=$((EXPECTED_GROSS - ACTIVE_RAIL_RATE)))"
[ "$SETTLEMENT" -le "$((EXPECTED_GROSS + ACTIVE_RAIL_RATE))" ] || fail "gross settlement over expected range (gross=$SETTLEMENT expected<=$((EXPECTED_GROSS + ACTIVE_RAIL_RATE)))"
POST_SETTLE_ALLOC_IDS_CSV=$(ccall "$CLIENT_CONTRACT" \
    "getClientAllocationIdsPerDeal(uint256)(uint64[])" "$DEAL_ID" 2>/dev/null | tr -d '[] ')
[ -n "$POST_SETTLE_ALLOC_IDS_CSV" ] || fail "could not re-query allocation IDs after settlement"
assert_eq "$POST_SETTLE_ALLOC_IDS_CSV" "$ALLOC_IDS_CSV" \
    "allocation IDs should be unchanged after settlement"

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

echo "--- Negative path: re-allocating completed deal should revert ---"
NEG_CALLDATA=$(cd "$POREP_DIR" && PROVIDER="$PROVIDER" DEAL_ID="$DEAL_ID" DEAL_COMPLETED=true \
    PIECE_CID_HEX="${MULTI_PIECE_CID_HEXES[0]}" PIECE_SIZE="${MULTI_PIECE_SIZES[0]}" \
    forge script "$SCRIPT_DIR/../mocks/ComputeTransferCalldata.s.sol" \
    --rpc-url "$RPC_URL" 2>&1 | grep "CALLDATA=" | sed 's/.*CALLDATA=//')
[ -n "$NEG_CALLDATA" ] || fail "could not compute negative-path calldata"
NEG_TX=$(cast send "$CLIENT_CONTRACT" "$NEG_CALLDATA" \
    --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY_TEST" \
    --gas-limit 9000000000 --json 2>/dev/null | jq -r '.transactionHash // empty')
assert_tx_reverted "$NEG_TX" "re-allocating a completed deal should revert"

echo ""
echo "============================================================"
echo "  VERIFICATION"
echo "============================================================"
echo "Deal ID:              $DEAL_ID"
echo "Validator:            $VALIDATOR"
echo "Rail ID:              $RAIL_ID"
echo "Allocation IDs:       $ALLOC_IDS_CSV"
echo "Piece count:          $PIECE_COUNT"
echo "Rail rate:            $ACTIVE_RAIL_RATE attoUSDC/epoch"
echo "Expected rate:        $EXPECTED_RATE attoUSDC/epoch"
echo "Settled epochs:       $RAIL_SETTLED_START -> $RAIL_SETTLED_END"
echo "Gross settlement:     $SETTLEMENT"
echo "Net settlement:       $PAID_AMOUNT"
echo "Protocol fee:         $ACTUAL_FEE"
for idx in "${!ALLOC_IDS[@]}"; do
    echo "Piece[$idx]:           ${MULTI_PIECE_CIDS[$idx]} -> alloc ${ALLOC_IDS[$idx]}"
done
echo ""
echo "RESULT: Verified one deal can register, claim, settle, and re-verify multiple pieces in one allocation flow."
echo "        Post-settlement allocation IDs: stable."
echo "        Negative path (re-allocate completed deal): correctly reverts."
echo "============================================================"
