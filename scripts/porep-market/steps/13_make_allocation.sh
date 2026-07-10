#!/bin/bash
# Params: (none)
# State in:  DEAL_ID, PIECE_SIZE, PIECE_CID_HEX
# State out: ALLOC_ID, PROVIDER
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_porep
require_env PRIVATE_KEY_TEST DATACAP_EVIDENCE_ADAPTER POREP_MARKET META_ALLOCATOR

state_load
state_require DEAL_ID PIECE_SIZE PIECE_CID_HEX

DEAL_JSON=$(decode_eth_call_json \
    "$POREP_MARKET" \
    "getDeal(uint256)" \
    "getDeal(uint256)((uint256,address,uint64,uint256,uint8,address,address,uint256))" \
    "$DEAL_ID")
PROVIDER=$(json_tuple_field "$DEAL_JSON" 2)

echo "=== Make Allocation ==="
echo "  Deal: $DEAL_ID  Provider: $PROVIDER"

META_ALLOWANCE=$(ccall "$META_ALLOCATOR" "allowance(address)(uint256)" "$DATACAP_EVIDENCE_ADAPTER" 2>/dev/null | awk '{print $1}')
if [ "${META_ALLOWANCE:-0}" -lt "$PIECE_SIZE" ] 2>/dev/null; then
    csend "$META_ALLOCATOR" "addAllowance(address,uint256)" "$DATACAP_EVIDENCE_ADAPTER" 999999999999999999
    echo "  MetaAllocator allowance granted to DataCapEvidenceAdapter"
else
    echo "  MetaAllocator allowance OK: $META_ALLOWANCE"
fi

ADAPTER_FIL_ADDR=$(docker exec lotus lotus evm stat "$DATACAP_EVIDENCE_ADAPTER" \
    | awk '/Filecoin address:/{print $3}' | tr -d '\r\n')
if [ -n "$ADAPTER_FIL_ADDR" ]; then
    update_env "CLIENT_FIL_ADDR" "$ADAPTER_FIL_ADDR"
    echo "  DataCap client: $ADAPTER_FIL_ADDR"
fi

cd "$POREP_DIR"
CALLDATA=$(PROVIDER="$PROVIDER" PIECE_SIZE="$PIECE_SIZE" DEAL_ID="$DEAL_ID" \
    PIECE_CID_HEX="$PIECE_CID_HEX" \
    forge script "$SCRIPT_DIR/../mocks/ComputeTransferCalldata.s.sol" \
    --rpc-url "$RPC_URL" 2>&1 | grep "CALLDATA=" | sed 's/.*CALLDATA=//')

[ -n "$CALLDATA" ] || { echo "ERROR: Failed to compute transfer calldata"; exit 1; }

TX_HASH=$(send_tx_hash "$DATACAP_EVIDENCE_ADAPTER" "$CALLDATA")
[ -n "$TX_HASH" ] || { echo "ERROR: submitDataCapBatch() tx returned no hash"; exit 1; }
wait_for_tx "$TX_HASH"
echo "  DataCap transferred"

csend "$DATACAP_EVIDENCE_ADAPTER" "finishDataCapPosting(uint256)" "$DEAL_ID"
echo "  DataCap posting finished"

ALLOCATION_STATUS=$(ccall "$DATACAP_EVIDENCE_ADAPTER" \
    "getDealAllocationStatus(uint256)(uint8)" "$DEAL_ID" 2>/dev/null | awk '{print $1}')
if [ "$ALLOCATION_STATUS" != "10" ]; then
    echo "ERROR: DataCap allocation status is $ALLOCATION_STATUS, expected 10 (Allocated)"
    exit 1
fi

ALLOC_ID=$(ccall "$DATACAP_EVIDENCE_ADAPTER" \
    "getAllocationIdsPerDeal(uint256,uint256,uint256)(uint64[],uint256)" "$DEAL_ID" 0 1 2>/dev/null | \
    grep -Eo '[0-9]+' | head -1)
[ -n "$ALLOC_ID" ] && [ "$ALLOC_ID" -gt 0 ] || { echo "ERROR: Could not get allocation ID"; exit 1; }

state_set ALLOC_ID "$ALLOC_ID"
state_set PROVIDER "$PROVIDER"

echo "  Allocation ID: $ALLOC_ID"
echo "=== Allocation complete ==="
