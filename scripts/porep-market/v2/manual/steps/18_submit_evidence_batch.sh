#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST POREP_MARKET DATACAP_EVIDENCE_ADAPTER

state_load
state_require DEAL_ID

BATCH_SIZE="${1:-${V2_EVIDENCE_BATCH_SIZE:-100}}"
EVIDENCE_DATA=$(cast abi-encode "f(uint256)" "$BATCH_SIZE")

echo "=== Submit V2 evidence batch ==="
echo "  Deal:       $DEAL_ID"
echo "  Batch size: $BATCH_SIZE"

TX_HASH=$(send_tx_hash "$POREP_MARKET" "submitEvidenceBatch(uint256,bytes)" "$DEAL_ID" "$EVIDENCE_DATA")
wait_for_tx "$TX_HASH"

CLAIM_JSON=$(decode_eth_call_json \
    "$DATACAP_EVIDENCE_ADAPTER" \
    "getClaimIds(uint256,uint256,uint256)" \
    "getClaimIds(uint256,uint256,uint256)(uint64[],uint256)" \
    "$DEAL_ID" 0 100)
CLAIM_IDS_CSV=$(printf '%s\n' "$CLAIM_JSON" | jq -r '
    if (.[0] | type) == "array" and (.[0][0] | type) == "array" then .[0][0]
    elif (.[0] | type) == "array" then .[0]
    else []
    end | map(tostring) | join(",")
')
CLAIM_COUNT=$(printf '%s\n' "$CLAIM_IDS_CSV" | tr ',' '\n' | sed '/^$/d' | wc -l | tr -d ' ')
[ "$CLAIM_COUNT" -gt 0 ] || { echo "ERROR: no claim ids recorded after submitEvidenceBatch"; exit 1; }

ALLOC_STATUS=$(cast call --rpc-url "$RPC_URL" "$DATACAP_EVIDENCE_ADAPTER" \
    "getDealAllocationStatus(uint256)(uint8)" "$DEAL_ID")
[ "$ALLOC_STATUS" = "20" ] || { echo "ERROR: allocation status expected 20 (CLAIMED), got $ALLOC_STATUS"; exit 1; }

state_set CLAIM_IDS_CSV "$CLAIM_IDS_CSV"
state_set CLAIM_COUNT "$CLAIM_COUNT"

echo "  TX: $TX_HASH"
echo "  Claim IDs: $CLAIM_IDS_CSV"
echo "=== V2 evidence submitted ==="
