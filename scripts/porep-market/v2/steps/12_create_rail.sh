#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env PRIVATE_KEY_TEST USDC_TOKEN POREP_MARKET

state_load
state_require DEAL_ID VALIDATOR

echo "Creating V2 prepared rail..."
echo "Validator: $VALIDATOR"
echo "Token:     $USDC_TOKEN"

TX_HASH=$(send_tx_hash "$VALIDATOR" "createRail(address)" "$USDC_TOKEN")
wait_for_tx "$TX_HASH"

RAIL_ID=$(get_v2_deal_field "$DEAL_ID" 7)
[ -n "$RAIL_ID" ] && [ "$RAIL_ID" != "0" ] || { echo "ERROR: deal railId was not set"; exit 1; }

RAIL_STATUS=$(cast call --rpc-url "$RPC_URL" "$VALIDATOR" "getRailStatus()(uint8)")
[ "$RAIL_STATUS" = "10" ] || { echo "ERROR: rail status expected 10 (PREPARED), got $RAIL_STATUS"; exit 1; }

state_set RAIL_ID "$RAIL_ID"
echo "Prepared rail created: $RAIL_ID"
