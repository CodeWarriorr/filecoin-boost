#!/bin/bash
# Ensure the local devnet deployer has enough MockUSDC for the V2 E2E suite.
# This is a setup boundary for disposable devnet state, not a scenario rescue path.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST USDC_TOKEN

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")
REQUIRED="${USDC_MIN_BALANCE:-1000000000000}"

case "$REQUIRED" in
    ''|*[!0-9]*)
        echo "ERROR: USDC_MIN_BALANCE must be an integer token-unit amount, got '$REQUIRED'" >&2
        exit 1
        ;;
esac

echo "=== Ensure V2 E2E MockUSDC funding ==="
echo "  Deployer: $DEPLOYER"
echo "  Required balance: $REQUIRED"

BALANCE=$(ccall "$USDC_TOKEN" "balanceOf(address)(uint256)" "$DEPLOYER" 2>/dev/null | awk '{print $1}')
case "$BALANCE" in
    ''|*[!0-9]*)
        echo "ERROR: could not read MockUSDC balance for $DEPLOYER: '$BALANCE'" >&2
        exit 1
        ;;
esac

echo "  Current balance: $BALANCE"

if [ "$BALANCE" -lt "$REQUIRED" ] 2>/dev/null; then
    MINT_AMOUNT=$((REQUIRED - BALANCE))
    echo "  Minting missing balance: $MINT_AMOUNT"
    csend "$USDC_TOKEN" "mint(address,uint256)" "$DEPLOYER" "$MINT_AMOUNT"
else
    echo "  Balance already sufficient"
fi

NEW_BALANCE=$(ccall "$USDC_TOKEN" "balanceOf(address)(uint256)" "$DEPLOYER" 2>/dev/null | awk '{print $1}')
if [ "$NEW_BALANCE" -lt "$REQUIRED" ] 2>/dev/null; then
    echo "ERROR: MockUSDC funding below requirement after setup: need $REQUIRED, have $NEW_BALANCE" >&2
    exit 1
fi

echo "  Final balance: $NEW_BALANCE"
echo "=== V2 E2E MockUSDC funding ready ==="
