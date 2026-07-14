#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST DATACAP_EVIDENCE_ADAPTER

state_load
state_require DEAL_ID

echo "=== Finish V2 DataCap posting ==="
csend "$DATACAP_EVIDENCE_ADAPTER" "finishDataCapPosting(uint256)" "$DEAL_ID"

POSTING_FINISHED=$(cast call --rpc-url "$RPC_URL" "$DATACAP_EVIDENCE_ADAPTER" \
    "isDataCapPostingFinished(uint256)(bool)" "$DEAL_ID")
[ "$POSTING_FINISHED" = "true" ] || { echo "ERROR: DataCap posting is not finished"; exit 1; }

ALLOC_STATUS=$(cast call --rpc-url "$RPC_URL" "$DATACAP_EVIDENCE_ADAPTER" \
    "getDealAllocationStatus(uint256)(uint8)" "$DEAL_ID")
[ "$ALLOC_STATUS" = "10" ] || { echo "ERROR: allocation status expected 10 (ALLOCATED), got $ALLOC_STATUS"; exit 1; }

echo "  Posting finished for deal $DEAL_ID"
echo "=== V2 DataCap posting closed ==="
