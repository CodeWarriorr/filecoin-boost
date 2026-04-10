#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/_common.sh"

STATE_FILE="/tmp/porep-sli-slashing-verified-$$.state"
export STATE_FILE
echo "State: $STATE_FILE"

echo "============================================================"
echo "  SLI SLASHING VERIFIED: Zero-pay on failed SLI dimensions"
echo "============================================================"

# Deal requires all four SLI dimensions.
REQ_RETR=8000
REQ_BW=500
REQ_LAT=200
REQ_IDX=90

# Good provider attestation.
GOOD_RETR=10000
GOOD_BW=1000
GOOD_LAT=100
GOOD_IDX=100

[ "${SKIP_SETUP:-}" = "1" ] || bash "$SETUP/06_prepare_operator.sh"
if [ "${SKIP_SETUP:-}" = "1" ]; then
    state_set DEPLOYER "$DEPLOYER"
    state_set SP_WALLET "$SP_WALLET"
    state_set MINER_ID "${MINER_ID:-1000}"
fi
GENERATE_PIECE=1 bash "$SETUP/07_generate_piece.sh"

LATENCY_MS="$REQ_LAT" INDEXING_PCT="$REQ_IDX" \
    bash "$STEPS/07_propose_deal.sh" "$REQ_RETR" "$REQ_BW" 2000000 360
state_require DEAL_ID
bash "$STEPS/08_accept_deal.sh"
bash "$STEPS/10_deploy_validator.sh"; state_require VALIDATOR
bash "$STEPS/11_deposit_and_approve_operator.sh" 100
bash "$STEPS/12_create_rail.sh"; state_require RAIL_ID
bash "$STEPS/13_make_allocation.sh"
[ "${SKIP_SETUP:-}" = "1" ] || bash "$SETUP/08_ensure_boost.sh"
bash "$STEPS/14_import_piece.sh"
CLAIM_MAX_ATTEMPTS=60 bash "$STEPS/16_wait_for_claim.sh"

state_load
state_require DEAL_ID RAIL_ID VALIDATOR SP_WALLET MINER_ID

assert_eq "$(get_deal_field "$DEAL_ID" 4)" "$REQ_RETR" "deal retrievability requirement mismatch"
assert_eq "$(get_deal_field "$DEAL_ID" 5)" "$REQ_BW" "deal bandwidth requirement mismatch"
assert_eq "$(get_deal_field "$DEAL_ID" 6)" "$REQ_LAT" "deal latency requirement mismatch"
assert_eq "$(get_deal_field "$DEAL_ID" 7)" "$REQ_IDX" "deal indexing requirement mismatch"

set_sli "$GOOD_RETR" "$GOOD_BW" "$GOOD_LAT" "$GOOD_IDX"

END_EPOCH_OFFSET=500 MIN_INTERVAL=1 SETTLE_WAIT=5 \
    bash "$STEPS/20_activate_payment.sh"

RAIL_RATE=$(rail_payment_rate "$RAIL_ID")
assert_gt "$RAIL_RATE" 0 "rail payment rate should be active"
echo "Rail rate: $RAIL_RATE units/epoch"

echo "Waiting 20s for baseline positive settlement..."
sleep 20
read -r BASE_CLIENT_DELTA BASE_SP_DELTA BASE_START BASE_END < <(settle_with_accounting_to_now "$RAIL_ID")
BASE_GROSS=$((-BASE_CLIENT_DELTA))
BASE_FEE=$((BASE_GROSS - BASE_SP_DELTA))
BASE_EXPECTED_FEE=$(((BASE_GROSS + 199) / 200))
assert_gt "$BASE_GROSS" 0 "matching SLI should debit the client"
assert_gt "$BASE_SP_DELTA" 0 "matching SLI should produce positive settlement"
assert_gt "$BASE_END" "$BASE_START" "baseline settlement should advance settledUpTo"
assert_eq "$BASE_FEE" "$BASE_EXPECTED_FEE" "baseline protocol fee mismatch"
echo "Baseline positive settlement: gross=$BASE_GROSS net=$BASE_SP_DELTA epochs=$BASE_START->$BASE_END"

run_slash_case() {
    local label="$1" retr="$2" bw="$3" lat="$4" idx="$5"
    echo ""
    echo "============================================================"
    echo "  CASE: $label"
    echo "============================================================"

    set_sli "$retr" "$bw" "$lat" "$idx"
    echo "Waiting 15s under failed SLI window..."
    sleep 15

    read -r bad_client_delta bad_sp_delta bad_start bad_end < <(settle_with_accounting_to_now "$RAIL_ID")
    assert_eq "$bad_client_delta" "0" "$label should not debit the client when settlement is slashed"
    assert_eq "$bad_sp_delta" "0" "$label should slash settlement to zero"
    assert_gt "$bad_end" "$bad_start" "$label should still advance settledUpTo even with zero payment"
    echo "Slashed settlement: client_delta=$bad_client_delta sp_delta=$bad_sp_delta epochs=$bad_start->$bad_end"

    set_sli "$GOOD_RETR" "$GOOD_BW" "$GOOD_LAT" "$GOOD_IDX"
    echo "Waiting 15s after restoring healthy SLI..."
    sleep 15

    read -r good_client_delta good_sp_delta good_start good_end < <(settle_with_accounting_to_now "$RAIL_ID")
    good_gross=$((-good_client_delta))
    good_fee=$((good_gross - good_sp_delta))
    good_expected_fee=$(((good_gross + 199) / 200))
    assert_gt "$good_gross" 0 "$label recovery should debit the client again"
    assert_gt "$good_sp_delta" 0 "$label recovery should restore positive settlement"
    assert_gt "$good_end" "$good_start" "$label recovery should advance settledUpTo"
    assert_eq "$good_fee" "$good_expected_fee" "$label recovery protocol fee mismatch"
    echo "Recovered settlement: gross=$good_gross net=$good_sp_delta epochs=$good_start->$good_end"
}

run_slash_case "retrievability below threshold" 0 "$GOOD_BW" "$GOOD_LAT" "$GOOD_IDX"
run_slash_case "bandwidth below threshold" "$GOOD_RETR" 0 "$GOOD_LAT" "$GOOD_IDX"
run_slash_case "latency above threshold" "$GOOD_RETR" "$GOOD_BW" 1000 "$GOOD_IDX"
run_slash_case "indexing below threshold" "$GOOD_RETR" "$GOOD_BW" "$GOOD_LAT" 0

FINAL_DEAL_STATE=$(get_deal_field "$DEAL_ID" 12)
assert_eq "$FINAL_DEAL_STATE" "2" "deal should remain Completed throughout slashing scenario"

echo ""
echo "============================================================"
echo "  VERIFICATION"
echo "============================================================"
echo "Deal ID:     $DEAL_ID"
echo "Validator:   $VALIDATOR"
echo "Rail ID:     $RAIL_ID"
echo "Rail rate:   $RAIL_RATE units/epoch"
echo "Deal state:  $FINAL_DEAL_STATE (Completed)"
echo ""
echo "RESULT: SLI slashing verified. Matching SLIs pay; any failed required SLI slashes settlement to zero; restoring healthy SLIs restores positive settlement."
echo "============================================================"
