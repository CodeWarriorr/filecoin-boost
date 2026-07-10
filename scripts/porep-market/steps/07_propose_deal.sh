#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env PRIVATE_KEY_TEST
require_env POREP_MARKET
require_env USDC_TOKEN

RETRIEVABILITY_BPS=${1:?retrievabilityBps required}
BANDWIDTH_MBPS=${2:?bandwidthMbps required}
PRICE_TOKENS=${3:?price tokens required}
DURATION_DAYS=${4:?durationDays required}

DEAL_SIZE_BYTES=2048
LATENCY_MS="${LATENCY_MS:-0}"
INDEXING_PCT="${INDEXING_PCT:-0}"
DECIMALS=6
MANIFEST="${MANIFEST:-https://example.com/manifest-${STATE_FILE##*/}.json}"

MANIFEST_HASH=$(cast keccak "$MANIFEST")
BANDWIDTH_BYTES_PER_SECOND=$((BANDWIDTH_MBPS * 1024 * 1024))

# PRICE=$(cast --to-wei "$PRICE_TOKENS" "$DECIMALS")

echo "Proposing deal..."

TX_HASH=$(send_tx_hash \
  "$POREP_MARKET" \
  "proposeDeal((bytes32,uint256,uint256,string,address,uint32,(uint16,uint64,uint16,uint8)))" \
  "($MANIFEST_HASH,$DEAL_SIZE_BYTES,$PRICE_TOKENS,$MANIFEST,$USDC_TOKEN,$DURATION_DAYS,($RETRIEVABILITY_BPS,$BANDWIDTH_BYTES_PER_SECOND,$LATENCY_MS,$INDEXING_PCT))")

echo "TX: $TX_HASH"

wait_for_tx "$TX_HASH"

echo "Reading receipt..."

RECEIPT=$(receipt_json "$TX_HASH")

# topic0 = keccak("DealCreated(...)")
EVENT_SIG=$(cast keccak "DealCreated(uint256,address,uint64,(uint16,uint64,uint16,uint8),bytes32,string,uint256,uint256)")

DEAL_ID=$(echo "$RECEIPT" | jq -r --arg sig "$EVENT_SIG" '
.logs[]
| select(.topics[0]==$sig)
| .topics[1]
' | cast to-dec)

[ -n "$DEAL_ID" ] || { echo "ERROR: DealCreated event not found"; exit 1; }

echo "DealCreated event caught, dealId = $DEAL_ID"
state_set DEAL_ID "$DEAL_ID"

# --------------------------
# CALL V2 deal views
# --------------------------
echo "Fetching deal..."

DEAL_JSON=$(decode_eth_call_json \
  "$POREP_MARKET" \
  "getDeal(uint256)" \
  "getDeal(uint256)((uint256,address,uint64,uint256,uint8,address,address,uint256))" \
  "$DEAL_ID")
SLIS_JSON=$(decode_eth_call_json \
  "$POREP_MARKET" \
  "getDealSLIs(uint256)" \
  "getDealSLIs(uint256)((uint16,uint64,uint16,uint8))" \
  "$DEAL_ID")
TERMS_JSON=$(decode_eth_call_json \
  "$POREP_MARKET" \
  "getDealTerms(uint256)" \
  "getDealTerms(uint256)((uint256,uint64))" \
  "$DEAL_ID")
DATA_JSON=$(decode_eth_call_json \
  "$POREP_MARKET" \
  "getDealData(uint256)" \
  "getDealData(uint256)((bytes32,string))" \
  "$DEAL_ID")
PAYMENT_JSON=$(decode_eth_call_json \
  "$POREP_MARKET" \
  "getDealPayment(uint256)" \
  "getDealPayment(uint256)((address,address,uint256,uint256,uint256))" \
  "$DEAL_ID")

CLIENT=$(json_tuple_field "$DEAL_JSON" 1)
PROVIDER=$(json_tuple_field "$DEAL_JSON" 2)
OFFER_ID=$(json_tuple_field "$DEAL_JSON" 3)
STATE=$(json_tuple_field "$DEAL_JSON" 4)
EVIDENCE_ADAPTER=$(json_tuple_field "$DEAL_JSON" 5)
VALIDATOR=$(json_tuple_field "$DEAL_JSON" 6)
RAIL_ID=$(json_tuple_field "$DEAL_JSON" 7)
REQ_RETR=$(json_tuple_field "$SLIS_JSON" 0)
REQ_BW=$(json_tuple_field "$SLIS_JSON" 1)
REQ_LAT=$(json_tuple_field "$SLIS_JSON" 2)
REQ_IDX=$(json_tuple_field "$SLIS_JSON" 3)
TERM_SIZE=$(json_tuple_field "$TERMS_JSON" 0)
TERM_DURATION_EPOCHS=$(json_tuple_field "$TERMS_JSON" 1)
ACTUAL_MANIFEST_HASH=$(json_tuple_field "$DATA_JSON" 0)
ACTUAL_MANIFEST=$(json_tuple_field "$DATA_JSON" 1)
PAYMENT_TOKEN=$(json_tuple_field "$PAYMENT_JSON" 0)
PAYEE=$(json_tuple_field "$PAYMENT_JSON" 1)
TERM_PRICE=$(json_tuple_field "$PAYMENT_JSON" 2)

case "$STATE" in
  10) STATE_NAME="Proposed" ;;
  20) STATE_NAME="Accepted" ;;
  30) STATE_NAME="Active" ;;
  40) STATE_NAME="Finalized" ;;
  50) STATE_NAME="Rejected" ;;
  60) STATE_NAME="Expired" ;;
  70) STATE_NAME="Terminated" ;;
  *) STATE_NAME="Unknown" ;;
esac

state_set PROVIDER "$PROVIDER"

echo ""
echo "Deal"
echo "----"
echo "dealId:             $DEAL_ID"
echo "client:             $CLIENT"
echo "provider:           $PROVIDER"
echo "offerId:            $OFFER_ID"
echo ""
echo "requirements:"
echo "  retrievabilityBps $REQ_RETR"
echo "  bandwidthBytes/s  $REQ_BW"
echo "  latencyMs         $REQ_LAT"
echo "  indexingPct       $REQ_IDX"
echo ""
echo "terms:"
echo "  dealSizeBytes          $TERM_SIZE"
echo "  pricePer32GiBPerMonth  $TERM_PRICE"
echo "  durationEpochs         $TERM_DURATION_EPOCHS"
echo "  paymentToken           $PAYMENT_TOKEN"
echo "  payee                  $PAYEE"
echo ""
echo "evidenceAdapter:    $EVIDENCE_ADAPTER"
echo "validator:          $VALIDATOR"
echo "state:              $STATE ($STATE_NAME)"
echo "railId:             $RAIL_ID"
echo "manifestHash:       $ACTUAL_MANIFEST_HASH"
echo "manifestLocation:   $ACTUAL_MANIFEST"
