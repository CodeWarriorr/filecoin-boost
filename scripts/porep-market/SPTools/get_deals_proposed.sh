#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../steps/_common.sh"

require_devnet
require_env POREP_MARKET

# --------------------------
# INPUT
# --------------------------
ORGANIZATION=${1:-${ORGANIZATION:?organization address required}}

RESULTS=$(ccall "$POREP_MARKET" \
  "getDealsForOrganizationByState(address,uint8)((uint256,address,uint64,(uint16,uint16,uint16,uint8),(uint256,uint256,uint32),address,uint8,uint256,string)[])" \
  "$ORGANIZATION" \
  "0")

if [ -z "$RESULTS" ] || [ "$RESULTS" = "[]" ]; then
  echo "No proposed deals found for organization $ORGANIZATION"
  exit 0
fi

# Remove [1e6]-style annotations
RESULTS=$(echo "$RESULTS" | sed 's/ \[[^]]*\]//g')

# Extract each top-level (...) group as one line
DEAL_LIST=$(echo "$RESULTS" | awk '{
  depth=0; start=0
  for(i=1; i<=length($0); i++) {
    c=substr($0,i,1)
    if(c=="(") { depth++; if(depth==1) start=i }
    else if(c==")") { depth--; if(depth==0) { print substr($0,start,i-start+1) } }
  }
}')

DEAL_COUNT=$(echo "$DEAL_LIST" | grep -c '.' || true)
echo "Found $DEAL_COUNT proposed deal(s)"
echo ""

IDX=0
while IFS= read -r DEAL; do
  [ -z "$DEAL" ] && continue
  IDX=$((IDX + 1))
  [ $IDX -gt 1 ] && echo "---------------------------------------------"

  FLAT=$(echo "$DEAL" | tr -d '()')

  IFS=',' read -r DEAL_ID CLIENT PROVIDER \
    REQ_RETR REQ_BW REQ_LAT REQ_IDX \
    TERM_SIZE TERM_PRICE TERM_DURATION \
    VALIDATOR STATE RAIL_ID MANIFEST <<< "$FLAT"

  DEAL_ID=$(echo "$DEAL_ID" | xargs)
  CLIENT=$(echo "$CLIENT" | xargs)
  PROVIDER=$(echo "$PROVIDER" | xargs)
  REQ_RETR=$(echo "$REQ_RETR" | xargs)
  REQ_BW=$(echo "$REQ_BW" | xargs)
  REQ_LAT=$(echo "$REQ_LAT" | xargs)
  REQ_IDX=$(echo "$REQ_IDX" | xargs)
  TERM_SIZE=$(echo "$TERM_SIZE" | xargs)
  TERM_PRICE=$(echo "$TERM_PRICE" | xargs)
  TERM_DURATION=$(echo "$TERM_DURATION" | xargs)
  VALIDATOR=$(echo "$VALIDATOR" | xargs)
  STATE=$(echo "$STATE" | xargs)
  RAIL_ID=$(echo "$RAIL_ID" | xargs)
  MANIFEST=$(echo "$MANIFEST" | xargs | tr -d '"')

  echo "Deal #$IDX"
  echo "--------"
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
  echo "state:              $STATE (Proposed)"
  echo "railId:             $RAIL_ID"
  echo "manifestLocation:   $MANIFEST"
  echo ""
done <<< "$DEAL_LIST"
