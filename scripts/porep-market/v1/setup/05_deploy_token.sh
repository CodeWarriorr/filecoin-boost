#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_porep
require_env PRIVATE_KEY_TEST

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")
echo "=== Deploy MockUSDC (6 decimals) ==="
echo "Deployer: $DEPLOYER"

cd "$POREP_DIR"

echo "Deploying MockUSDC..."
DEPLOY_OUTPUT=$(forge script "$SCRIPT_DIR/../mocks/DeployMockUSDC.s.sol" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY_TEST" \
    --broadcast \
    --gas-estimate-multiplier 100000 \
    --disable-block-gas-limit \
    2>&1)

echo "$DEPLOY_OUTPUT" | grep -q "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL" || { echo "ERROR: MockUSDC deploy failed"; echo "$DEPLOY_OUTPUT" | tail -20; exit 1; }

USDC_TOKEN=$(echo "$DEPLOY_OUTPUT" | grep "USDC_DEPLOYED_TO=" | tail -1 | sed 's/.*USDC_DEPLOYED_TO=//' | tr -d '[:space:]')
[ -n "$USDC_TOKEN" ] && [ "$USDC_TOKEN" != "null" ] || { echo "ERROR: could not extract USDC address"; exit 1; }
echo "  MockUSDC: $USDC_TOKEN"
require_code_at "$USDC_TOKEN" "MockUSDC"
update_env "USDC_TOKEN" "$USDC_TOKEN"

MINT_AMOUNT=1000000000000  # 1M USDC (1e12 with 6 decimals)
echo "Minting $MINT_AMOUNT to deployer..."
csend "$USDC_TOKEN" "mint(address,uint256)" "$DEPLOYER" "$MINT_AMOUNT"

BALANCE=$(cast call --rpc-url "$RPC_URL" "$USDC_TOKEN" "balanceOf(address)(uint256)" "$DEPLOYER")
echo "  Deployer USDC balance: $BALANCE"

echo "Done."
