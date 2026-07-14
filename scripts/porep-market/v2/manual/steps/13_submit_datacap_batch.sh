#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_porep
require_env PRIVATE_KEY_TEST POREP_MARKET DATACAP_EVIDENCE_ADAPTER

state_load
state_require DEAL_ID PIECE_SIZE PIECE_CID_HEX

PROVIDER=$(get_v2_deal_field "$DEAL_ID" 2)
[ -n "$PROVIDER" ] && [ "$PROVIDER" != "0" ] || { echo "ERROR: V2 deal $DEAL_ID has no provider"; exit 1; }

echo "=== Submit V2 DataCap batch ==="
echo "  Deal:     $DEAL_ID"
echo "  Provider: $PROVIDER"
echo "  Piece:    $PIECE_SIZE bytes"
echo "  Adapter:  $DATACAP_EVIDENCE_ADAPTER"

cd "$POREP_DIR"
CALLDATA=$(PROVIDER="$PROVIDER" PIECE_SIZE="$PIECE_SIZE" DEAL_ID="$DEAL_ID" \
    PIECE_CID_HEX="$PIECE_CID_HEX" \
    forge script "$SCRIPT_DIR/../../mocks/ComputeDataCapBatchCalldata.s.sol" \
    --rpc-url "$RPC_URL" 2>&1 | grep "CALLDATA=" | sed 's/.*CALLDATA=//')

[ -n "$CALLDATA" ] || { echo "ERROR: failed to compute submitDataCapBatch calldata"; exit 1; }

TX_HASH=$(send_tx_hash "$DATACAP_EVIDENCE_ADAPTER" "$CALLDATA")
[ -n "$TX_HASH" ] || { echo "ERROR: submitDataCapBatch tx returned no hash"; exit 1; }
wait_for_tx "$TX_HASH"

ALLOC_JSON=$(decode_eth_call_json \
    "$DATACAP_EVIDENCE_ADAPTER" \
    "getAllocationIdsPerDeal(uint256,uint256,uint256)" \
    "getAllocationIdsPerDeal(uint256,uint256,uint256)(uint64[],uint256)" \
    "$DEAL_ID" 0 100)

ALLOC_IDS_CSV=$(printf '%s\n' "$ALLOC_JSON" | jq -r '
    if (.[0] | type) == "array" and (.[0][0] | type) == "array" then .[0][0]
    elif (.[0] | type) == "array" then .[0]
    else []
    end | map(tostring) | join(",")
')
ALLOC_COUNT=$(printf '%s\n' "$ALLOC_IDS_CSV" | tr ',' '\n' | sed '/^$/d' | wc -l | tr -d ' ')
ALLOC_ID=$(printf '%s\n' "$ALLOC_IDS_CSV" | tr ',' '\n' | sed '/^$/d' | head -n1)

[ -n "$ALLOC_ID" ] && [ "$ALLOC_ID" -gt 0 ] || { echo "ERROR: adapter returned no allocation id"; exit 1; }

state_set PROVIDER "$PROVIDER"
state_set ALLOC_ID "$ALLOC_ID"
state_set ALLOC_IDS_CSV "$ALLOC_IDS_CSV"
state_set ALLOC_COUNT "$ALLOC_COUNT"

echo "  TX: $TX_HASH"
echo "  Allocation IDs: $ALLOC_IDS_CSV"
echo "=== V2 DataCap batch submitted ==="
