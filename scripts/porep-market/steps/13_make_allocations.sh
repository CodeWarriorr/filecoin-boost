#!/bin/bash
# Params: (none)
# State in:  DEAL_ID, PIECE_CID_HEXES, PIECE_SIZES
# State out: ALLOC_IDS_CSV, ALLOC_COUNT, PROVIDER
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_porep
require_env PRIVATE_KEY_TEST CLIENT_CONTRACT POREP_MARKET

state_load
state_require DEAL_ID PIECE_CID_HEXES PIECE_SIZES

PROVIDER=$(get_deal_field "$DEAL_ID" 3)
PIECE_COUNT=$(printf '%s\n' "$PIECE_CID_HEXES" | awk -F'|' '{print NF}')

echo "=== Make Allocations ==="
echo "  Deal:        $DEAL_ID"
echo "  Provider:    $PROVIDER"
echo "  Piece count: $PIECE_COUNT"

cd "$POREP_DIR"
CALLDATA=$(PROVIDER="$PROVIDER" DEAL_ID="$DEAL_ID" DEAL_COMPLETED=true \
    PIECE_CID_HEXES="$PIECE_CID_HEXES" PIECE_SIZES="$PIECE_SIZES" \
    forge script "$SCRIPT_DIR/../mocks/ComputeMultiTransferCalldata.s.sol" \
    --rpc-url "$RPC_URL" 2>&1 | grep "CALLDATA=" | sed 's/.*CALLDATA=//')

[ -n "$CALLDATA" ] || { echo "ERROR: Failed to compute multi-allocation transfer calldata"; exit 1; }

TX_HASH=$(send_tx_hash "$CLIENT_CONTRACT" "$CALLDATA")
[ -n "$TX_HASH" ] || { echo "ERROR: Client.transfer() tx returned no hash"; exit 1; }
wait_for_tx "$TX_HASH"
echo "  DataCap transferred"

DEAL_STATE=$(get_deal_field "$DEAL_ID" 12)
if [ "$DEAL_STATE" != "2" ]; then
    echo "ERROR: Deal state is $DEAL_STATE, expected 2 (Completed)"
    exit 1
fi

ALLOC_IDS_CSV=$(ccall "$CLIENT_CONTRACT" \
    "getClientAllocationIdsPerDeal(uint256)(uint64[])" "$DEAL_ID" 2>/dev/null | tr -d '[] ')
ALLOC_COUNT=$(printf '%s\n' "$ALLOC_IDS_CSV" | tr ',' '\n' | sed '/^$/d' | wc -l | tr -d ' ')
UNIQUE_COUNT=$(printf '%s\n' "$ALLOC_IDS_CSV" | tr ',' '\n' | sed '/^$/d' | sort -u | wc -l | tr -d ' ')

[ -n "$ALLOC_IDS_CSV" ] || { echo "ERROR: Could not get allocation IDs"; exit 1; }
[ "$ALLOC_COUNT" -eq "$PIECE_COUNT" ] || {
    echo "ERROR: allocation count mismatch (allocations=$ALLOC_COUNT pieces=$PIECE_COUNT)"
    exit 1
}
[ "$UNIQUE_COUNT" -eq "$ALLOC_COUNT" ] || {
    echo "ERROR: allocation IDs are not unique (allocations=$ALLOC_COUNT unique=$UNIQUE_COUNT)"
    exit 1
}

state_set ALLOC_IDS_CSV "$ALLOC_IDS_CSV"
state_set ALLOC_COUNT "$ALLOC_COUNT"
state_set PROVIDER "$PROVIDER"

echo "  Allocation IDs: $ALLOC_IDS_CSV"
echo "=== Allocations complete ==="
