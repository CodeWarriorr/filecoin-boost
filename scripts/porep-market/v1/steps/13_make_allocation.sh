#!/bin/bash
# Params: (none)
# State in:  DEAL_ID, PIECE_SIZE, PIECE_CID_HEX
# State out: ALLOC_ID, PROVIDER
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_porep
require_env PRIVATE_KEY_TEST CLIENT_CONTRACT POREP_MARKET

state_load
state_require DEAL_ID PIECE_SIZE PIECE_CID_HEX

PROVIDER=$(get_deal_field "$DEAL_ID" 3)

echo "=== Make Allocation ==="
echo "  Deal: $DEAL_ID  Provider: $PROVIDER"

cd "$POREP_DIR"
CALLDATA=$(PROVIDER="$PROVIDER" PIECE_SIZE="$PIECE_SIZE" DEAL_ID="$DEAL_ID" DEAL_COMPLETED=true \
    PIECE_CID_HEX="$PIECE_CID_HEX" \
    forge script "$SCRIPT_DIR/../mocks/ComputeTransferCalldata.s.sol" \
    --rpc-url "$RPC_URL" 2>&1 | grep "CALLDATA=" | sed 's/.*CALLDATA=//')

[ -n "$CALLDATA" ] || { echo "ERROR: Failed to compute transfer calldata"; exit 1; }

TX_HASH=$(send_tx_hash "$CLIENT_CONTRACT" "$CALLDATA")
[ -n "$TX_HASH" ] || { echo "ERROR: Client.transfer() tx returned no hash"; exit 1; }
wait_for_tx "$TX_HASH"
echo "  DataCap transferred"

DEAL_STATE=$(get_deal_field "$DEAL_ID" 12)
if [ "$DEAL_STATE" != "2" ]; then
    echo "ERROR: Deal state is $DEAL_STATE, expected 2 (Completed)"
    exit 1
fi

ALLOC_ID=$(ccall "$CLIENT_CONTRACT" \
    "getClientAllocationIdsPerDeal(uint256)(uint64[])" "$DEAL_ID" 2>/dev/null | \
    tr -d '[]' | tr ',' '\n' | tail -1 | tr -d ' ')
[ -n "$ALLOC_ID" ] && [ "$ALLOC_ID" -gt 0 ] || { echo "ERROR: Could not get allocation ID"; exit 1; }

state_set ALLOC_ID "$ALLOC_ID"
state_set PROVIDER "$PROVIDER"

echo "  Allocation ID: $ALLOC_ID"
echo "=== Allocation complete ==="
