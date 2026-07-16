#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST POREP_MARKET

state_load
state_require DEAL_ID COMMITTED_BYTES

BATCH_SIZE="${1:-${V2_EVIDENCE_REFRESH_BATCH_SIZE:-${CLAIM_COUNT:-100}}}"
[ "$BATCH_SIZE" -gt 0 ] || { echo "ERROR: evidence refresh batch size must be > 0, got $BATCH_SIZE"; exit 1; }
EVIDENCE_DATA=$(cast abi-encode "f(uint256)" "$BATCH_SIZE")

echo "=== Refresh V2 evidence status ==="
echo "  Deal: $DEAL_ID"
echo "  Batch size: $BATCH_SIZE"
echo "  Committed bytes: $COMMITTED_BYTES"

TX_HASH=$(send_tx_hash "$POREP_MARKET" "refreshEvidenceStatus(uint256,bytes)" "$DEAL_ID" "$EVIDENCE_DATA")
wait_for_tx "$TX_HASH"

STATUS_JSON=$(decode_eth_call_json \
    "$POREP_MARKET" \
    "currentEvidenceStatus(uint256)" \
    "currentEvidenceStatus(uint256)((uint256,int64,uint16,uint8,uint256,uint256))" \
    "$DEAL_ID")

ACTIVE_COVERED_BYTES=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][0]')
LAST_REFRESH_EPOCH=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][1]')
EVIDENCE_REASON_CODE=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][2]')
EVIDENCE_RESULT=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][3]')
EVIDENCE_CHECKED_CLAIMS=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][4]')
EVIDENCE_TOTAL_CLAIMS=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][5]')

[ "$ACTIVE_COVERED_BYTES" = "$COMMITTED_BYTES" ] || {
    echo "ERROR: activeCoveredBytes expected $COMMITTED_BYTES, got $ACTIVE_COVERED_BYTES"
    exit 1
}
[ "$EVIDENCE_RESULT" = "40" ] || { echo "ERROR: evidence result expected 40 (ACTIVE), got $EVIDENCE_RESULT"; exit 1; }
[ "$EVIDENCE_CHECKED_CLAIMS" = "$EVIDENCE_TOTAL_CLAIMS" ] || {
    echo "ERROR: evidence refresh only checked $EVIDENCE_CHECKED_CLAIMS of $EVIDENCE_TOTAL_CLAIMS claims"
    exit 1
}
[ "$LAST_REFRESH_EPOCH" -gt 0 ] || { echo "ERROR: last evidence refresh epoch expected > 0, got $LAST_REFRESH_EPOCH"; exit 1; }

state_set EVIDENCE_REFRESH_TX "$TX_HASH"
state_set EVIDENCE_ACTIVE_COVERED_BYTES "$ACTIVE_COVERED_BYTES"
state_set EVIDENCE_LAST_REFRESH_EPOCH "$LAST_REFRESH_EPOCH"
state_set EVIDENCE_REASON_CODE "$EVIDENCE_REASON_CODE"
state_set EVIDENCE_RESULT "$EVIDENCE_RESULT"
state_set EVIDENCE_CHECKED_CLAIMS "$EVIDENCE_CHECKED_CLAIMS"
state_set EVIDENCE_TOTAL_CLAIMS "$EVIDENCE_TOTAL_CLAIMS"

echo "  TX: $TX_HASH"
echo "  Active covered bytes: $ACTIVE_COVERED_BYTES"
echo "  Last refresh epoch: $LAST_REFRESH_EPOCH"
echo "  Result: ACTIVE"
echo "  Checked claims: $EVIDENCE_CHECKED_CLAIMS / $EVIDENCE_TOTAL_CLAIMS"
echo "=== V2 evidence status refreshed ==="
