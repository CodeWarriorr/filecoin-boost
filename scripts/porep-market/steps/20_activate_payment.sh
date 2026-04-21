#!/bin/bash
# Env params (all optional):
#   END_EPOCH_OFFSET  - blocks ahead of current for deal end epoch (default: 100)
#   MIN_INTERVAL      - min epochs between settlements (default: 1)
#   SETTLE_WAIT       - seconds to wait for blocks to advance (default: 60)
# State in: DEAL_ID, VALIDATOR, RAIL_ID
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST

state_load
state_require DEAL_ID VALIDATOR RAIL_ID

CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL")
END_EPOCH=$((CURRENT_BLOCK + ${END_EPOCH_OFFSET:-100}))
MIN_INTERVAL="${MIN_INTERVAL:-1}"
SETTLE_WAIT="${SETTLE_WAIT:-60}"

state_set ACTIVATION_BLOCK "$CURRENT_BLOCK"
state_set ACTIVATION_END_EPOCH "$END_EPOCH"
state_set ACTIVATION_MIN_INTERVAL "$MIN_INTERVAL"

echo "=== Activate Payment ==="
echo "  Deal:      $DEAL_ID"
echo "  Validator: $VALIDATOR"
echo "  Rail:      $RAIL_ID"
echo "  End epoch: $END_EPOCH (current $CURRENT_BLOCK + ${END_EPOCH_OFFSET:-100})"
echo "  Min interval: $MIN_INTERVAL"

TX_HASH=$(send_tx_hash \
    "$VALIDATOR" \
    "setDealEndEpoch(uint256,int64)" "$DEAL_ID" "$END_EPOCH")
wait_for_tx "$TX_HASH"
echo "  setDealEndEpoch done"

TX_HASH=$(send_tx_hash \
    "$VALIDATOR" \
    "setMinEpochsBetweenSettlements(uint256)" "$MIN_INTERVAL")
wait_for_tx "$TX_HASH"
echo "  setMinEpochsBetweenSettlements done"

TX_HASH=$(send_tx_hash \
    "$VALIDATOR" \
    "modifyRailPayment(uint256)" \
    "$RAIL_ID")
wait_for_tx "$TX_HASH"
echo "  modifyRailPayment done"

echo "  Waiting ${SETTLE_WAIT}s for blocks to advance..."
sleep "$SETTLE_WAIT"

echo "=== Payment activated ==="
