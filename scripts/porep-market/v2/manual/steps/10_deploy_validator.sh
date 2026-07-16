#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env PRIVATE_KEY_TEST VALIDATOR_FACTORY POREP_MARKET

state_load
DEAL_ID="${1:-$(state_get DEAL_ID)}"
[ -n "$DEAL_ID" ] || { echo "ERROR: DEAL_ID required (arg or state)"; exit 1; }

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")

echo "Creating V2 validator..."
echo "Factory: $VALIDATOR_FACTORY"
echo "Sender:  $DEPLOYER"
echo "DealId:  $DEAL_ID"

TX=$(send_tx_output "$VALIDATOR_FACTORY" "create(uint256)" "$DEAL_ID")
TX_HASH=$(extract_tx_hash "$TX")
wait_for_tx "$TX_HASH"

VALIDATOR=$(cast call --rpc-url "$RPC_URL" "$VALIDATOR_FACTORY" "getInstance(uint256)(address)" "$DEAL_ID" | head -1)
[ -n "$VALIDATOR" ] && [ "$VALIDATOR" != "0x0000000000000000000000000000000000000000" ] || {
    echo "ERROR: ValidatorFactory returned zero validator for deal $DEAL_ID" >&2
    exit 1
}

DEAL_VALIDATOR=$(get_v2_deal_field "$DEAL_ID" 6)
[ "$(lower_hex "$DEAL_VALIDATOR")" = "$(lower_hex "$VALIDATOR")" ] || {
    echo "ERROR: deal validator expected $VALIDATOR, got $DEAL_VALIDATOR" >&2
    exit 1
}

state_set VALIDATOR "$VALIDATOR"
echo "Validator created: $VALIDATOR"
