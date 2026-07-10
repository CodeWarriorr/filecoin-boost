#!/bin/bash
# Params:
#   MINER_ID           - numeric miner actor ID (default: 1000)
#   USDC_MIN_BALANCE   - mint USDC if deployer balance below this (default: 864000000000)
# State out: DEPLOYER, SP_WALLET, MINER_ID
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST PRIVATE_KEY_SP POREP_MARKET DATACAP_EVIDENCE_ADAPTER \
            SP_REGISTRY SLI_ORACLE USDC_TOKEN

state_load

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")
SP_WALLET=$(cast wallet address "$PRIVATE_KEY_SP")
MINER_ID="${MINER_ID:-1000}"

echo "=== Prepare Operator ==="
echo "  Deployer: $DEPLOYER"
echo "  SP:       $SP_WALLET"
echo "  Miner:    $MINER_ID"

# Set globalEvidenceAdapter (idempotent)
CURRENT=$(ccall "$POREP_MARKET" "getGlobalEvidenceAdapter()(address)" 2>/dev/null || echo "")
if [ "$(echo "$CURRENT" | tr '[:upper:]' '[:lower:]')" != "$(echo "$DATACAP_EVIDENCE_ADAPTER" | tr '[:upper:]' '[:lower:]')" ]; then
    csend "$POREP_MARKET" "setGlobalEvidenceAdapter(address)" "$DATACAP_EVIDENCE_ADAPTER"
    echo "  globalEvidenceAdapter -> $DATACAP_EVIDENCE_ADAPTER"
else
    echo "  globalEvidenceAdapter already set"
fi

# Ensure USDC balance
USDC_BALANCE=$(ccall "$USDC_TOKEN" "balanceOf(address)(uint256)" "$DEPLOYER" 2>/dev/null | awk '{print $1}')
REQUIRED="${USDC_MIN_BALANCE:-864000000000}"
if [ "$USDC_BALANCE" -lt "$REQUIRED" ] 2>/dev/null; then
    MINT_AMOUNT=$((REQUIRED - USDC_BALANCE + REQUIRED))
    csend "$USDC_TOKEN" "mint(address,uint256)" "$DEPLOYER" "$MINT_AMOUNT"
    echo "  Minted $MINT_AMOUNT USDC"
else
    echo "  USDC balance OK: $USDC_BALANCE"
fi

echo "  Fake provider pause skipped for V2"

# Fund SP wallet
docker exec lotus lotus send "$SP_WALLET" 10 2>/dev/null || true
sleep 30  # wait one epoch for the Lotus message to land (no EVM hash to poll)
echo "  Funded SP with 10 FIL"

# Refresh SLI attestation
echo "  SLI attestation skipped until deal exists"

# Set SP payee (idempotent)
CURRENT_PAYEE=$(ccall "$SP_REGISTRY" "getProviderView(uint64)((uint64,address,address,bool,bool,uint256,uint256,uint256))" "$MINER_ID" 2>/dev/null | sed 's/[()]//g' | cut -d',' -f3 | tr -d ' ')
if [ "$(echo "$CURRENT_PAYEE" | tr '[:upper:]' '[:lower:]')" != "$(echo "$SP_WALLET" | tr '[:upper:]' '[:lower:]')" ]; then
    csend "$SP_REGISTRY" "setPayee(uint64,address)" "$MINER_ID" "$SP_WALLET"
    CURRENT_PAYEE="$SP_WALLET"
fi
echo "  Payee: $CURRENT_PAYEE"

state_set DEPLOYER "$DEPLOYER"
state_set SP_WALLET "$SP_WALLET"
state_set MINER_ID "$MINER_ID"
update_env "ORGANIZATION" "$DEPLOYER"

echo "=== Operator ready ==="
