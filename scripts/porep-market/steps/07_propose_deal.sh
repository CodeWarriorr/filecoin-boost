#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env PRIVATE_KEY_TEST
require_env POREP_MARKET

RETRIEVABILITY_BPS=${1:?retrievabilityBps required}
BANDWIDTH_MBPS=${2:?bandwidthMbps required}
PRICE_TOKENS=${3:?price tokens required}
DURATION_DAYS=${4:?durationDays required}

DEAL_SIZE_BYTES=2048
LATENCY_MS="${LATENCY_MS:-0}"
INDEXING_PCT="${INDEXING_PCT:-0}"
DECIMALS=6
MANIFEST="https://example.com/manifest.json"

# PRICE=$(cast --to-wei "$PRICE_TOKENS" "$DECIMALS")

echo "Proposing deal..."

TX_HASH=$(send_tx_hash \
  "$POREP_MARKET" \
  "proposeDeal((uint16,uint16,uint16,uint8),(uint256,uint256,uint32),string)" \
  "($RETRIEVABILITY_BPS,$BANDWIDTH_MBPS,$LATENCY_MS,$INDEXING_PCT)" \
  "($DEAL_SIZE_BYTES,$PRICE_TOKENS,$DURATION_DAYS)" \
  "$MANIFEST")

echo "TX: $TX_HASH"

wait_for_tx "$TX_HASH"

echo "Reading receipt..."

RECEIPT=$(receipt_json "$TX_HASH")

# topic0 = keccak("DealProposalCreated(...)")
EVENT_SIG=$(cast keccak "DealProposalCreated(uint256,address,uint64,(uint16,uint16,uint16,uint8),string,uint256)")

DEAL_ID=$(echo "$RECEIPT" | jq -r --arg sig "$EVENT_SIG" '
.logs[]
| select(.topics[0]==$sig)
| .topics[1]
' | cast to-dec)

echo "DealProposalCreated event caught, dealId = $DEAL_ID"
state_set DEAL_ID "$DEAL_ID"

# --------------------------
# CALL getDealProposal
# --------------------------
echo "Fetching deal proposal..."

RESULT=$(cast call \
  --rpc-url "$RPC_URL" \
  "$POREP_MARKET" \
  "getDealProposal(uint256)((uint256,address,uint64,(uint16,uint16,uint16,uint8),(uint256,uint256,uint32),address,uint8,uint256,string))" \
  "$DEAL_ID")

# remove parentheses
RESULT=$(echo "$RESULT" | tr -d '()')

# split fields
IFS=',' read -r DEAL_ID CLIENT PROVIDER \
REQ_RETR REQ_BW REQ_LAT REQ_IDX \
TERM_SIZE TERM_PRICE TERM_DURATION \
VALIDATOR STATE RAIL_ID MANIFEST <<< "$RESULT"

STATE=$(echo "$STATE" | xargs)

case "$STATE" in
  0) STATE_NAME="Proposed" ;;
  1) STATE_NAME="Accepted" ;;
  2) STATE_NAME="Completed" ;;
  3) STATE_NAME="Rejected" ;;
  4) STATE_NAME="Terminated" ;;
  *) STATE_NAME="Unknown" ;;
esac

echo ""
echo "Deal Proposal"
echo "-------------"
echo "dealId:             $DEAL_ID"
echo "client:             $CLIENT"
echo "provider:           $PROVIDER"
echo ""
echo "requirements:"
echo "  retrievabilityBps $REQ_RETR"
echo "  bandwidthMbps     $REQ_BW"
echo "  latencyMs         $REQ_LAT"
echo "  indexingPct       $REQ_IDX"
echo ""
echo "terms:"
echo "  dealSizeBytes         $TERM_SIZE"
echo "  pricePerSectorPerMonth $TERM_PRICE"
echo "  durationDays          $TERM_DURATION"
echo ""
echo "validator:          $VALIDATOR"
echo "state:              $STATE ($STATE_NAME)"
echo "railId:             $RAIL_ID"
echo "manifestLocation:   $MANIFEST"
