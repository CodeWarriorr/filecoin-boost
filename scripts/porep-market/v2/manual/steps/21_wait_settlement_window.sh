#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env POREP_MARKET FILECOIN_PAY

state_load
state_require DEAL_ID RAIL_ID

echo "=== Wait for V2 settlement window ==="
echo "  Deal: $DEAL_ID"
echo "  Rail: $RAIL_ID"

SERVICE_JSON=$(get_v2_deal_service_json "$DEAL_ID")
MIN_SETTLEMENT_EPOCHS=$(printf '%s\n' "$SERVICE_JSON" | jq -r '.[0][3]')
RAIL_SETTLED_UP_TO=$(rail_settled_up_to "$RAIL_ID")
EARLIEST_SETTLEMENT=$((RAIL_SETTLED_UP_TO + MIN_SETTLEMENT_EPOCHS))
CURRENT_EPOCH=$(cast block-number --rpc-url "$RPC_URL")

echo "  Rail settled up to: $RAIL_SETTLED_UP_TO"
echo "  Min settlement epochs: $MIN_SETTLEMENT_EPOCHS"
echo "  Earliest settlement epoch: $EARLIEST_SETTLEMENT"
echo "  Current epoch: $CURRENT_EPOCH"

if [ "$CURRENT_EPOCH" -lt "$EARLIEST_SETTLEMENT" ]; then
    wait_for_block "$EARLIEST_SETTLEMENT"
    CURRENT_EPOCH=$(cast block-number --rpc-url "$RPC_URL")
fi

state_set EARLIEST_SETTLEMENT_EPOCH "$EARLIEST_SETTLEMENT"
state_set SETTLEMENT_READY_EPOCH "$CURRENT_EPOCH"

echo "  Ready epoch: $CURRENT_EPOCH"
echo "=== V2 settlement window ready ==="
