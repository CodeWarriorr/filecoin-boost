#!/bin/bash
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env POREP_MARKET

# --------------------------
# INPUT
# --------------------------
DEAL_ID=${1:?dealId required}

echo "Fetching deal proposal..."
echo "DealId: $DEAL_ID"
echo ""

RESULT=$(cast call \
  --rpc-url "$RPC_URL" \
  "$POREP_MARKET" \
  "getDealProposal(uint256)((uint256,address,uint64,(uint16,uint16,uint16,uint8),(uint256,uint256,uint32),address,uint8,uint256,uint256,string))" \
  "$DEAL_ID")

# remove parentheses
RESULT=$(echo "$RESULT" | tr -d '()')

# split fields
IFS=',' read -r DEAL_ID CLIENT PROVIDER \
REQ_RETR REQ_BW REQ_LAT REQ_IDX \
TERM_SIZE TERM_PRICE TERM_DURATION \
VALIDATOR STATE RAIL_ID PROPOSED_AT_BLOCK MANIFEST <<< "$RESULT"

STATE=$(echo "$STATE" | xargs)

# --------------------------
# MAP ENUM
# --------------------------
case "$STATE" in
  0) STATE_NAME="Proposed" ;;
  1) STATE_NAME="Accepted" ;;
  2) STATE_NAME="Completed" ;;
  3) STATE_NAME="Rejected" ;;
  4) STATE_NAME="Terminated" ;;
  *) STATE_NAME="Unknown" ;;
esac

# --------------------------
# PRINT
# --------------------------
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
echo "  dealSizeBytes          $TERM_SIZE"
echo "  pricePerSectorPerMonth $TERM_PRICE"
echo "  durationDays           $TERM_DURATION"

echo ""
echo "validator:          $VALIDATOR"
echo "state:              $STATE ($STATE_NAME)"
echo "railId:             $RAIL_ID"
echo "proposedAtBlock:    $PROPOSED_AT_BLOCK"
echo "manifestLocation:   $MANIFEST"
