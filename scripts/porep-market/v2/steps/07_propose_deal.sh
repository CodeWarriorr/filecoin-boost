#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env PRIVATE_KEY_TEST POREP_MARKET DATACAP_EVIDENCE_ADAPTER

RETRIEVABILITY_BPS="${1:-${V2_RETRIEVABILITY_BPS:-10000}}"
BANDWIDTH_BYTES_PER_SECOND="${2:-${V2_BANDWIDTH_BYTES_PER_SECOND:-1048576}}"
PRICE_PER_32GIB_MONTH="${3:-${V2_PRICE_PER_32GIB_MONTH:-86400000000}}"
DURATION_DAYS="${4:-${V2_DURATION_DAYS:-180}}"
REQUESTED_SIZE_BYTES="${V2_REQUESTED_SIZE_BYTES:-2048}"
LATENCY_MS="${V2_LATENCY_MS:-100}"
INDEXING_PCT="${V2_INDEXING_PCT:-100}"
PAYMENT_TOKEN="${V2_PAYMENT_TOKEN:-${USDC_TOKEN:-0x0000000000000000000000000000000000000000}}"
MANIFEST_LOCATION="${V2_MANIFEST_LOCATION:-https://example.com/v2-manifest.json}"
MANIFEST_HASH="${V2_MANIFEST_HASH:-$(cast keccak "$MANIFEST_LOCATION")}"

echo "Proposing V2 deal..."

TX_HASH=$(send_tx_hash \
  "$POREP_MARKET" \
  "proposeDeal((bytes32,uint256,uint256,string,address,uint32,(uint16,uint64,uint16,uint8)))" \
  "($MANIFEST_HASH,$REQUESTED_SIZE_BYTES,$PRICE_PER_32GIB_MONTH,$MANIFEST_LOCATION,$PAYMENT_TOKEN,$DURATION_DAYS,($RETRIEVABILITY_BPS,$BANDWIDTH_BYTES_PER_SECOND,$LATENCY_MS,$INDEXING_PCT))")

echo "TX: $TX_HASH"
wait_for_tx "$TX_HASH"

RECEIPT=$(receipt_json "$TX_HASH")
EVENT_SIG=$(cast keccak "DealCreated(uint256,address,uint64,(uint16,uint64,uint16,uint8),string,uint256,uint256)")

DEAL_ID=$(echo "$RECEIPT" | jq -r --arg sig "$EVENT_SIG" '
.logs[]
| select(.topics[0]==$sig)
| .topics[1]
' | cast to-dec)

[ -n "$DEAL_ID" ] || { echo "ERROR: DealCreated event not found"; exit 1; }
state_set DEAL_ID "$DEAL_ID"

STATE=$(get_v2_deal_field "$DEAL_ID" 4)
OFFER_ID=$(get_v2_deal_field "$DEAL_ID" 3)
PROVIDER=$(get_v2_deal_field "$DEAL_ID" 2)
EVIDENCE_ADAPTER=$(get_v2_deal_field "$DEAL_ID" 5)
DATA_JSON=$(get_v2_deal_data_json "$DEAL_ID")
TERMS_JSON=$(get_v2_deal_terms_json "$DEAL_ID")
CAPACITY_JSON=$(get_v2_deal_capacity_json "$DEAL_ID")
PAYMENT_JSON=$(get_v2_deal_payment_json "$DEAL_ID")
SLIS_JSON=$(get_v2_deal_slis_json "$DEAL_ID")

[ "$STATE" = "20" ] || { echo "ERROR: V2 deal $DEAL_ID state expected 20 (ACCEPTED), got $STATE"; exit 1; }
[ "$(lower_hex "$EVIDENCE_ADAPTER")" = "$(lower_hex "$DATACAP_EVIDENCE_ADAPTER")" ] || {
    echo "ERROR: evidence adapter expected $DATACAP_EVIDENCE_ADAPTER, got $EVIDENCE_ADAPTER" >&2
    exit 1
}

ACTUAL_MANIFEST_HASH=$(printf '%s\n' "$DATA_JSON" | jq -r '.[0][0]')
ACTUAL_MANIFEST_LOCATION=$(printf '%s\n' "$DATA_JSON" | jq -r '.[0][1]')
ACTUAL_SIZE_BYTES=$(printf '%s\n' "$TERMS_JSON" | jq -r '.[0][0]')
ACTUAL_DURATION_EPOCHS=$(printf '%s\n' "$TERMS_JSON" | jq -r '.[0][1]')
ACTUAL_RESERVED_BYTES=$(printf '%s\n' "$CAPACITY_JSON" | jq -r '.[0][0]')
ACTUAL_COMMITTED_BYTES=$(printf '%s\n' "$CAPACITY_JSON" | jq -r '.[0][1]')
ACTUAL_PAYMENT_TOKEN=$(printf '%s\n' "$PAYMENT_JSON" | jq -r '.[0][0]')
ACTUAL_PRICE=$(printf '%s\n' "$PAYMENT_JSON" | jq -r '.[0][2]')
ACTUAL_RETRIEVABILITY_BPS=$(printf '%s\n' "$SLIS_JSON" | jq -r '.[0][0]')
ACTUAL_BANDWIDTH_BYTES_PER_SECOND=$(printf '%s\n' "$SLIS_JSON" | jq -r '.[0][1]')
ACTUAL_LATENCY_MS=$(printf '%s\n' "$SLIS_JSON" | jq -r '.[0][2]')
ACTUAL_INDEXING_PCT=$(printf '%s\n' "$SLIS_JSON" | jq -r '.[0][3]')
EXPECTED_DURATION_EPOCHS=$((DURATION_DAYS * 2880))

[ "$OFFER_ID" = "0" ] || { echo "ERROR: current V2 main should store offerId 0, got $OFFER_ID"; exit 1; }
[ "$(lower_hex "$ACTUAL_MANIFEST_HASH")" = "$(lower_hex "$MANIFEST_HASH")" ] || { echo "ERROR: manifestHash mismatch"; exit 1; }
[ "$ACTUAL_MANIFEST_LOCATION" = "$MANIFEST_LOCATION" ] || { echo "ERROR: manifestLocation mismatch"; exit 1; }
[ "$ACTUAL_SIZE_BYTES" = "$REQUESTED_SIZE_BYTES" ] || { echo "ERROR: requestedSizeBytes mismatch"; exit 1; }
[ "$ACTUAL_DURATION_EPOCHS" = "$EXPECTED_DURATION_EPOCHS" ] || { echo "ERROR: durationEpochs mismatch"; exit 1; }
[ "$ACTUAL_RESERVED_BYTES" = "$REQUESTED_SIZE_BYTES" ] || { echo "ERROR: reservedBytes mismatch"; exit 1; }
[ "$ACTUAL_COMMITTED_BYTES" = "0" ] || { echo "ERROR: committedBytes expected 0, got $ACTUAL_COMMITTED_BYTES"; exit 1; }
[ "$(lower_hex "$ACTUAL_PAYMENT_TOKEN")" = "$(lower_hex "$PAYMENT_TOKEN")" ] || { echo "ERROR: paymentToken mismatch"; exit 1; }
[ "$ACTUAL_PRICE" = "$PRICE_PER_32GIB_MONTH" ] || { echo "ERROR: pricePer32GiBPerMonth mismatch"; exit 1; }
[ "$ACTUAL_RETRIEVABILITY_BPS" = "$RETRIEVABILITY_BPS" ] || { echo "ERROR: retrievabilityBps mismatch"; exit 1; }
[ "$ACTUAL_BANDWIDTH_BYTES_PER_SECOND" = "$BANDWIDTH_BYTES_PER_SECOND" ] || { echo "ERROR: bandwidthBytesPerSecond mismatch"; exit 1; }
[ "$ACTUAL_LATENCY_MS" = "$LATENCY_MS" ] || { echo "ERROR: latencyMs mismatch"; exit 1; }
[ "$ACTUAL_INDEXING_PCT" = "$INDEXING_PCT" ] || { echo "ERROR: indexingPct mismatch"; exit 1; }

EXPECTED_PROVIDER="$(state_get PROVIDER || true)"
if [ -n "$EXPECTED_PROVIDER" ]; then
    [ "$PROVIDER" = "$EXPECTED_PROVIDER" ] || { echo "ERROR: provider expected $EXPECTED_PROVIDER, got $PROVIDER"; exit 1; }
fi

echo "DealCreated event caught, dealId = $DEAL_ID"
echo "provider: $PROVIDER"
echo "offerId: 0 (current main has no offer API)"
echo "state: 20 (ACCEPTED)"
echo "dealData: $DATA_JSON"
echo "terms: $TERMS_JSON"
echo "capacity: $CAPACITY_JSON"
echo "payment: $PAYMENT_JSON"
echo "slis: $SLIS_JSON"
