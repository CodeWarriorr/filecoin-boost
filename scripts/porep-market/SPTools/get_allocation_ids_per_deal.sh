#!/bin/bash
# Params: <deal_id>
# State in:  (none — deal_id passed as argument or from state)
# State out: (none — read-only query)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../steps/_common.sh"

require_devnet
require_env CLIENT_CONTRACT

# --------------------------
# INPUT
# --------------------------
state_load

DEAL_ID="${1:-$(state_get DEAL_ID)}"
if [ -z "$DEAL_ID" ]; then
  echo "ERROR: deal_id required. Pass as argument or set DEAL_ID in state."
  echo "Usage: $0 <deal_id>"
  exit 1
fi

echo "=== Allocation IDs per Deal ==="
echo "  Client contract: $CLIENT_CONTRACT"
echo "  Deal ID:         $DEAL_ID"
echo ""

RAW=$(ccall "$CLIENT_CONTRACT" \
  "getClientAllocationIdsPerDeal(uint256)(uint64[])" \
  "$DEAL_ID" 2>/dev/null)

if [ -z "$RAW" ] || [ "$RAW" = "[]" ]; then
  echo "No allocations found for deal $DEAL_ID"
  exit 0
fi

# Remove [1e6]-style annotations and brackets
CLEAN=$(echo "$RAW" | sed 's/ \[[^]]*\]//g; s/\[//g; s/\]//g')

echo "Allocation IDs:"
COUNT=0
while IFS=',' read -r -d ',' ID || [ -n "$ID" ]; do
  ID=$(echo "$ID" | tr -d ' ')
  [ -z "$ID" ] && continue
  COUNT=$((COUNT + 1))
  echo "  [$COUNT] $ID"
done <<< "$CLEAN,"

echo ""
echo "Total: $COUNT allocation(s) for deal $DEAL_ID"
