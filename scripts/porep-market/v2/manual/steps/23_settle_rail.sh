#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST POREP_MARKET FILECOIN_PAY USDC_TOKEN

state_load
state_require DEAL_ID RAIL_ID COMMITTED_BYTES PAYMENT_RATE

echo "=== Settle V2 rail ==="
echo "  Deal: $DEAL_ID"
echo "  Rail: $RAIL_ID"

SERVICE_JSON=$(get_v2_deal_service_json "$DEAL_ID")
SERVICE_START=$(printf '%s\n' "$SERVICE_JSON" | jq -r '.[0][0]')
SERVICE_END=$(printf '%s\n' "$SERVICE_JSON" | jq -r '.[0][1]')
MIN_SETTLEMENT_EPOCHS=$(printf '%s\n' "$SERVICE_JSON" | jq -r '.[0][3]')
LAST_SETTLED=$(printf '%s\n' "$SERVICE_JSON" | jq -r '.[0][4]')

RAIL_JSON=$(decode_eth_call_json \
    "$FILECOIN_PAY" \
    "getRail(uint256)" \
    "getRail(uint256)((address,address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,address))" \
    "$RAIL_ID")
RAIL_SETTLED_UP_TO=$(printf '%s\n' "$RAIL_JSON" | jq -r '.[0][8]')

STATUS_JSON=$(decode_eth_call_json \
    "$POREP_MARKET" \
    "currentEvidenceStatus(uint256)" \
    "currentEvidenceStatus(uint256)((uint256,int64,uint16,uint8,uint256,uint256))" \
    "$DEAL_ID")
ACTIVE_COVERED_BYTES=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][0]')
LAST_REFRESH_EPOCH=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][1]')
EVIDENCE_RESULT=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][3]')
EVIDENCE_CHECKED_CLAIMS=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][4]')
EVIDENCE_TOTAL_CLAIMS=$(printf '%s\n' "$STATUS_JSON" | jq -r '.[0][5]')
REFRESH_GRACE=$(cast call --rpc-url "$RPC_URL" "$POREP_MARKET" "EVIDENCE_REFRESH_GRACE_EPOCHS()(uint256)" | awk '{print $1}')

CURRENT_EPOCH=$(cast block-number --rpc-url "$RPC_URL")
EARLIEST_SETTLEMENT=$((RAIL_SETTLED_UP_TO + MIN_SETTLEMENT_EPOCHS))
MAX_FRESH_TARGET=$((LAST_REFRESH_EPOCH + REFRESH_GRACE))
TARGET_EPOCH="$CURRENT_EPOCH"
if [ "$TARGET_EPOCH" -gt "$MAX_FRESH_TARGET" ]; then
    TARGET_EPOCH="$MAX_FRESH_TARGET"
fi
BLOCKED=0

echo "  Service epochs: $SERVICE_START -> $SERVICE_END"
echo "  Last deal-settled epoch: $LAST_SETTLED"
echo "  Rail settled up to: $RAIL_SETTLED_UP_TO"
echo "  Min settlement epochs: $MIN_SETTLEMENT_EPOCHS"
echo "  Earliest settlement epoch: $EARLIEST_SETTLEMENT"
echo "  Current epoch: $CURRENT_EPOCH"
echo "  Target epoch: $TARGET_EPOCH"
echo "  Evidence last refresh epoch: $LAST_REFRESH_EPOCH"
echo "  Evidence freshness grace: $REFRESH_GRACE"
echo "  Committed bytes: $COMMITTED_BYTES"
echo "  Active evidence bytes: $ACTIVE_COVERED_BYTES"
echo "  Evidence result: $EVIDENCE_RESULT"
echo "  Checked claims: $EVIDENCE_CHECKED_CLAIMS / $EVIDENCE_TOTAL_CLAIMS"
echo "  Rail payment rate: $PAYMENT_RATE"

if [ "$ACTIVE_COVERED_BYTES" != "$COMMITTED_BYTES" ]; then
    echo "ERROR: settlement blocked: currentEvidenceStatus activeCoveredBytes=$ACTIVE_COVERED_BYTES but committedBytes=$COMMITTED_BYTES"
    BLOCKED=1
fi

if [ "$EVIDENCE_RESULT" != "40" ]; then
    echo "ERROR: settlement blocked: evidence result expected 40 (ACTIVE), got $EVIDENCE_RESULT"
    BLOCKED=1
fi

if [ "$EVIDENCE_CHECKED_CLAIMS" != "$EVIDENCE_TOTAL_CLAIMS" ]; then
    echo "ERROR: settlement blocked: evidence refresh checked $EVIDENCE_CHECKED_CLAIMS of $EVIDENCE_TOTAL_CLAIMS claims"
    BLOCKED=1
fi

if [ "$TARGET_EPOCH" -lt "$EARLIEST_SETTLEMENT" ]; then
    echo "ERROR: settlement blocked: target epoch $TARGET_EPOCH is before earliest settlement epoch $EARLIEST_SETTLEMENT"
    BLOCKED=1
fi

if [ "$LAST_REFRESH_EPOCH" -le 0 ] || [ "$TARGET_EPOCH" -gt "$MAX_FRESH_TARGET" ]; then
    echo "ERROR: settlement blocked: evidence refresh is too old for target epoch $TARGET_EPOCH"
    BLOCKED=1
fi

[ "$BLOCKED" = "0" ] || exit 1

SP_BEFORE=$(fp_balance "$(printf '%s\n' "$RAIL_JSON" | jq -r '.[0][2]')")
TX_HASH=$(send_tx_hash "$FILECOIN_PAY" "settleRail(uint256,uint256)" "$RAIL_ID" "$TARGET_EPOCH")
wait_for_tx "$TX_HASH"
SP_AFTER=$(fp_balance "$(printf '%s\n' "$RAIL_JSON" | jq -r '.[0][2]')")
PAID_AMOUNT=$((SP_AFTER - SP_BEFORE))
[ "$PAID_AMOUNT" -gt 0 ] || { echo "ERROR: settlement paid amount expected > 0, got $PAID_AMOUNT"; exit 1; }

state_set SETTLEMENT_TX "$TX_HASH"
state_set PAID_AMOUNT "$PAID_AMOUNT"
state_set SETTLED_TARGET_EPOCH "$TARGET_EPOCH"

echo "  TX: $TX_HASH"
echo "  Paid amount: $PAID_AMOUNT"
echo "=== V2 rail settled ==="
