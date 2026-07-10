#!/bin/bash
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env PRIVATE_KEY_TEST
require_env USDC_TOKEN

state_load

# --------------------------
# INPUT
# --------------------------
VALIDATOR="${1:-$(state_get VALIDATOR)}"
[ -n "$VALIDATOR" ] || { echo "ERROR: VALIDATOR required (arg or state)"; exit 1; }

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")

echo "Creating rail..."
echo "Validator: $VALIDATOR"
echo "Token:     $USDC_TOKEN"
echo "Sender:    $DEPLOYER"

# --------------------------
# SEND TRANSACTION
# --------------------------
TX_HASH=$(send_tx_hash \
  "$VALIDATOR" \
  "createRail()")

wait_for_tx "$TX_HASH"

DEAL_ID=$(state_get DEAL_ID)
if [ -n "$DEAL_ID" ]; then
    RAIL_ID=$(get_deal_field "$DEAL_ID" 13)
    [ -n "$RAIL_ID" ] && state_set RAIL_ID "$RAIL_ID"
fi

echo "Rail created successfully!"
