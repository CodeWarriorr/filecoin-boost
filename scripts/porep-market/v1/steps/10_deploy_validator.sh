#!/bin/bash
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env PRIVATE_KEY_TEST
require_env VALIDATOR_FACTORY

state_load

DEAL_ID="${1:-$(state_get DEAL_ID)}"
[ -n "$DEAL_ID" ] || { echo "ERROR: DEAL_ID required (arg or state)"; exit 1; }

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")

echo "Creating validator..."
echo "Factory: $VALIDATOR_FACTORY"
echo "Sender:  $DEPLOYER"
echo "DealId:  $DEAL_ID"

# --------------------------
# SEND TX
# --------------------------

TX=$(send_tx_output \
  "$VALIDATOR_FACTORY" \
  "create(uint256)" \
  "$DEAL_ID")

TX_HASH=$(extract_tx_hash "$TX")
wait_for_tx "$TX_HASH"

echo "Transaction sent"

# --------------------------
# EXTRACT VALIDATOR ADDRESS
# --------------------------

VALIDATOR=$(cast call \
  --rpc-url "$RPC_URL" \
  "$VALIDATOR_FACTORY" \
  "getInstance(uint256)(address)" \
  "$DEAL_ID" | head -1)

echo "Validator address: $VALIDATOR"
state_set VALIDATOR "$VALIDATOR"

# --------------------------
# SAVE TO validators.json
# --------------------------

FILE="$SCRIPT_DIR/validators.json"

if [ ! -f "$FILE" ]; then
  echo "{}" > "$FILE"
fi

TMP=$(mktemp)

jq --arg id "$DEAL_ID" --arg addr "$VALIDATOR" \
'. + {($id): $addr}' "$FILE" > "$TMP"

mv "$TMP" "$FILE"

echo "Saved to validators.json"
echo "Validator created successfully!"
