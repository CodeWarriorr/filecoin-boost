#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet

state_load
state_require SP_WALLET DEPLOYER
require_env PRIVATE_KEY_SP FILECOIN_PAY USDC_TOKEN

AMOUNT="${1:-$(state_get PAID_AMOUNT)}"
[ -n "$AMOUNT" ] || { echo "ERROR: AMOUNT required (arg or state PAID_AMOUNT)"; exit 1; }

erc20_balance() {
    cast call --rpc-url "$RPC_URL" "$USDC_TOKEN" "balanceOf(address)(uint256)" "$1" | awk '{print $1}'
}

fp_balance() {
    cast call --rpc-url "$RPC_URL" "$FILECOIN_PAY" \
        "accounts(address,address)(uint256,uint256,uint256,uint256)" \
        "$USDC_TOKEN" "$1" 2>/dev/null | head -1 | awk '{print $1}'
}

echo "Method:   withdraw(address,uint256)"
echo "Token:    $USDC_TOKEN"
echo "Amount:   $AMOUNT"
echo "SP:       $SP_WALLET"
echo "Client:   $DEPLOYER"

echo
echo "=== Balances BEFORE ==="
SP_ERC20_BEFORE=$(erc20_balance "$SP_WALLET")
SP_FP_BEFORE=$(fp_balance "$SP_WALLET")
CLIENT_ERC20_BEFORE=$(erc20_balance "$DEPLOYER")
CLIENT_FP_BEFORE=$(fp_balance "$DEPLOYER")
echo "  SP     ERC-20: $SP_ERC20_BEFORE   FilecoinPay: $SP_FP_BEFORE"
echo "  Client ERC-20: $CLIENT_ERC20_BEFORE   FilecoinPay: $CLIENT_FP_BEFORE"

echo
echo "Sending withdraw transaction..."

TX_HASH=$(SENDER_KEY="$PRIVATE_KEY_SP" send_tx_hash \
  "$FILECOIN_PAY" \
  "withdraw(address,uint256)" \
  "$USDC_TOKEN" "$AMOUNT")

wait_for_tx "$TX_HASH"

echo
echo "=== Balances AFTER ==="
SP_ERC20_AFTER=$(erc20_balance "$SP_WALLET")
SP_FP_AFTER=$(fp_balance "$SP_WALLET")
CLIENT_ERC20_AFTER=$(erc20_balance "$DEPLOYER")
CLIENT_FP_AFTER=$(fp_balance "$DEPLOYER")
echo "  SP     ERC-20: $SP_ERC20_AFTER   FilecoinPay: $SP_FP_AFTER"
echo "  Client ERC-20: $CLIENT_ERC20_AFTER   FilecoinPay: $CLIENT_FP_AFTER"

SP_ERC20_DIFF=$((SP_ERC20_AFTER - SP_ERC20_BEFORE))
SP_FP_DIFF=$((SP_FP_AFTER - SP_FP_BEFORE))
CLIENT_ERC20_DIFF=$((CLIENT_ERC20_AFTER - CLIENT_ERC20_BEFORE))
CLIENT_FP_DIFF=$((CLIENT_FP_AFTER - CLIENT_FP_BEFORE))

echo
echo "=== Delta ==="
echo "  SP     ERC-20: $SP_ERC20_DIFF   FilecoinPay: $SP_FP_DIFF"
echo "  Client ERC-20: $CLIENT_ERC20_DIFF   FilecoinPay: $CLIENT_FP_DIFF"
