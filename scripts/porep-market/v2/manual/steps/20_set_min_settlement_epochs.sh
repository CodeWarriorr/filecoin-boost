#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST POREP_MARKET

state_load
state_require DEAL_ID

MIN_EPOCHS="${1:-${V2_MIN_SETTLEMENT_EPOCHS:-1}}"
[ "$MIN_EPOCHS" -gt 0 ] || { echo "ERROR: min settlement epochs must be > 0, got $MIN_EPOCHS"; exit 1; }

echo "=== Configure V2 settlement cadence ==="
echo "  Deal: $DEAL_ID"
echo "  Min epochs: $MIN_EPOCHS"
echo "  Mode: devnet scenario configuration through PoRepMarket admin API"

TX_HASH=$(send_tx_hash "$POREP_MARKET" "setMinEpochsBetweenSettlements(uint256,uint256)" "$DEAL_ID" "$MIN_EPOCHS")
wait_for_tx "$TX_HASH"

SERVICE_JSON=$(get_v2_deal_service_json "$DEAL_ID")
ACTUAL_MIN=$(printf '%s\n' "$SERVICE_JSON" | jq -r '.[0][3]')
[ "$ACTUAL_MIN" = "$MIN_EPOCHS" ] || { echo "ERROR: min settlement epochs expected $MIN_EPOCHS, got $ACTUAL_MIN"; exit 1; }

state_set MIN_SETTLEMENT_EPOCHS "$ACTUAL_MIN"
state_set SET_MIN_SETTLEMENT_EPOCHS_TX "$TX_HASH"

echo "  TX: $TX_HASH"
echo "=== V2 settlement cadence configured ==="
