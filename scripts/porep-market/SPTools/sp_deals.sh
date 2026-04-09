#!/bin/bash
# sp_deals.sh — Unified SP deal viewer
# Shows all deals (Proposed / Accepted / Completed) for an organization.
# For Completed deals, also fetches Allocation IDs from the client smart contract.
#
# Usage:
#   ./sp_deals.sh <organization_address>
#   ORGANIZATION=0x... ./sp_deals.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../steps/_common.sh"

require_devnet
require_env POREP_MARKET
require_env CLIENT_CONTRACT

# --------------------------
# INPUT
# --------------------------
ORGANIZATION="${1:-${ORGANIZATION:-}}"
if [ -z "$ORGANIZATION" ]; then
  echo "ERROR: organization address required"
  echo "Usage: $0 <organization_address>"
  exit 1
fi

# --------------------------
# HELPERS
# --------------------------

# Parse the raw tuple list from cast call into one deal-per-line format
parse_deal_list() {
  echo "$1" \
    | sed 's/ \[[^]]*\]//g' \
    | awk '{
        depth=0; start=0
        for(i=1; i<=length($0); i++) {
          c=substr($0,i,1)
          if(c=="(") { depth++; if(depth==1) start=i }
          else if(c==")") { depth--; if(depth==0) { print substr($0,start,i-start+1) } }
        }
      }'
}

# Print one deal block; $1=index, $2=flat deal string, $3=state_name
print_deal() {
  local idx="$1" flat="$2" state_name="$3"

  IFS=',' read -r DEAL_ID CLIENT PROVIDER \
    REQ_RETR REQ_BW REQ_LAT REQ_IDX \
    TERM_SIZE TERM_PRICE TERM_DURATION \
    VALIDATOR STATE RAIL_ID MANIFEST <<< "$flat"

  DEAL_ID=$(echo "$DEAL_ID"   | xargs)
  CLIENT=$(echo "$CLIENT"     | xargs)
  PROVIDER=$(echo "$PROVIDER" | xargs)
  TERM_SIZE=$(echo "$TERM_SIZE"         | xargs)
  TERM_PRICE=$(echo "$TERM_PRICE"       | xargs)
  TERM_DURATION=$(echo "$TERM_DURATION" | xargs)
  REQ_RETR=$(echo "$REQ_RETR" | xargs)
  REQ_BW=$(echo "$REQ_BW"     | xargs)
  REQ_LAT=$(echo "$REQ_LAT"   | xargs)
  REQ_IDX=$(echo "$REQ_IDX"   | xargs)
  VALIDATOR=$(echo "$VALIDATOR" | xargs)
  RAIL_ID=$(echo "$RAIL_ID"   | xargs)
  MANIFEST=$(echo "$MANIFEST" | xargs | tr -d '"')

  printf "  Deal #%s  [ID: %s]\n" "$idx" "$DEAL_ID"
  printf "  %s\n" "$(printf '─%.0s' {1..48})"
  printf "  %-24s %s\n" "Client:"    "$CLIENT"
  printf "  %-24s %s\n" "Provider:"  "$PROVIDER"
  printf "  %-24s %s\n" "Validator:" "$VALIDATOR"
  printf "  %-24s %s\n" "Rail ID:"   "$RAIL_ID"
  echo ""
  printf "  Terms\n"
  printf "  %-24s %s bytes\n"  "  Size:"     "$TERM_SIZE"
  printf "  %-24s %s attoUSDC/sector/mo\n" "  Price:" "$TERM_PRICE"
  printf "  %-24s %s days\n"  "  Duration:" "$TERM_DURATION"
  echo ""
  printf "  Requirements\n"
  printf "  %-24s %s\n" "  Retrievability:"  "$REQ_RETR bps"
  printf "  %-24s %s\n" "  Bandwidth:"       "$REQ_BW Mbps"
  printf "  %-24s %s\n" "  Latency:"         "$REQ_LAT ms"
  printf "  %-24s %s\n" "  Indexing:"        "$REQ_IDX%"
  echo ""
  printf "  %-24s %s\n" "Manifest:" "$MANIFEST"

  # For completed deals: fetch allocation IDs
  if [ "$state_name" = "Completed" ]; then
    echo ""
    printf "  Allocation IDs\n"
    local raw
    raw=$(ccall "$CLIENT_CONTRACT" \
      "getClientAllocationIdsPerDeal(uint256)(uint64[])" \
      "$DEAL_ID" 2>/dev/null || echo "")

    if [ -z "$raw" ] || [ "$raw" = "[]" ]; then
      printf "  %s\n" "(none found)"
    else
      local clean
      clean=$(echo "$raw" | sed 's/ \[[^]]*\]//g; s/\[//g; s/\]//g')
      local alloc_count=0
      while IFS=',' read -r -d ',' ID || [ -n "$ID" ]; do
        ID=$(echo "$ID" | tr -d ' ')
        [ -z "$ID" ] && continue
        alloc_count=$((alloc_count + 1))
        printf "    [%s] %s\n" "$alloc_count" "$ID"
      done <<< "$clean,"
    fi
  fi
}

# Fetch and display all deals for a given state
# $1 = state number (0/1/2), $2 = state label
show_section() {
  local state_num="$1" state_name="$2"
  local section_line
  section_line="$(printf '═%.0s' {1..60})"

  echo ""
  echo "$section_line"
  printf "  %s Deals\n" "$state_name"
  echo "$section_line"

  local raw
  raw=$(ccall "$POREP_MARKET" \
    "getDealsForOrganizationByState(address,uint8)((uint256,address,uint64,(uint16,uint16,uint16,uint8),(uint256,uint256,uint32),address,uint8,uint256,string)[])" \
    "$ORGANIZATION" \
    "$state_num" 2>/dev/null || echo "")

  if [ -z "$raw" ] || [ "$raw" = "[]" ]; then
    echo "  (no ${state_name,,} deals)"
    return
  fi

  local deal_list
  deal_list=$(parse_deal_list "$raw")

  local count
  count=$(echo "$deal_list" | grep -c '.' || true)
  printf "  %s deal(s) found\n" "$count"

  local idx=0
  while IFS= read -r deal; do
    [ -z "$deal" ] && continue
    idx=$((idx + 1))
    echo ""
    print_deal "$idx" "$(echo "$deal" | tr -d '()')" "$state_name"
  done <<< "$deal_list"
}

# --------------------------
# MAIN
# --------------------------
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              SP Deal Dashboard                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
printf "  Market:       %s\n" "$POREP_MARKET"
printf "  Organization: %s\n" "$ORGANIZATION"
printf "  Client SC:    %s\n" "$CLIENT_CONTRACT"

show_section 0 "Proposed"
show_section 1 "Accepted"
show_section 2 "Completed"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Done."
echo "══════════════════════════════════════════════════════════════"
echo ""
