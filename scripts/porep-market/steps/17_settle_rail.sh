#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env PRIVATE_KEY_TEST FILECOIN_PAY USDC_TOKEN

state_load
state_require SP_WALLET

RAIL_ID="${1:-$(state_get RAIL_ID)}"
[ -n "$RAIL_ID" ] || { echo "ERROR: RAIL_ID required (arg or state)"; exit 1; }

UNTIL_EPOCH=$(cast bn --rpc-url $RPC_URL)

echo "Method:       settleRail(uint256,uint256)"
echo "Rail ID:      $RAIL_ID"
echo "Until epoch:  $UNTIL_EPOCH"

SP_BEFORE=$(ccall "$FILECOIN_PAY" "accounts(address,address)(uint256,uint256,uint256,uint256)" \
    "$USDC_TOKEN" "$SP_WALLET" 2>/dev/null | head -1 | sed 's/[()]//g' | awk '{print $1}')

TX_HASH=$(send_tx_hash \
  "$FILECOIN_PAY" \
  "settleRail(uint256,uint256)" \
  "$RAIL_ID" \
  "$UNTIL_EPOCH")

echo "Transaction: $TX_HASH"
wait_for_tx "$TX_HASH"

SP_AFTER=$(ccall "$FILECOIN_PAY" "accounts(address,address)(uint256,uint256,uint256,uint256)" \
    "$USDC_TOKEN" "$SP_WALLET" 2>/dev/null | head -1 | sed 's/[()]//g' | awk '{print $1}')

PAID_AMOUNT=$((SP_AFTER - SP_BEFORE))
[ "$PAID_AMOUNT" -gt 0 ] || { echo "ERROR: SP balance did not increase after settlement"; exit 1; }

state_set PAID_AMOUNT "$PAID_AMOUNT"

echo "Rail ID:      $RAIL_ID"
echo "SP earned:    $PAID_AMOUNT attoUSDC"
echo "Done."
