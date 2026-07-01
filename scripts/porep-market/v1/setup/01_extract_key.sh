#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet

DEFAULT_WALLET=$(docker exec lotus lotus wallet default | tr -d '\r\n')
echo "Default wallet: $DEFAULT_WALLET"

EXPORTED=$(docker exec lotus lotus wallet export "$DEFAULT_WALLET" | tr -d '\r\n')

# lotus exports base64 with type prefix byte — strip it, keep 32-byte key
PRIVATE_KEY=$(echo "$EXPORTED" | base64 -d | tail -c 32 | xxd -p -c 64)
update_env "PRIVATE_KEY_TEST" "0x${PRIVATE_KEY}"

DERIVED_ADDR=$(cast wallet address "0x${PRIVATE_KEY}" 2>/dev/null || echo "cast failed")
echo "ETH address: $DERIVED_ADDR"

# Generate a separate SP wallet key if not already set
if [ -z "${PRIVATE_KEY_SP:-}" ]; then
    SP_INFO=$(cast wallet new 2>/dev/null)
    PRIVATE_KEY_SP=$(echo "$SP_INFO" | grep "Private key:" | awk '{print $3}')
    [ -n "$PRIVATE_KEY_SP" ] || { echo "ERROR: failed to generate SP key via cast wallet new"; exit 1; }
    update_env "PRIVATE_KEY_SP" "$PRIVATE_KEY_SP"
    SP_ADDR=$(echo "$SP_INFO" | grep "Address:" | awk '{print $2}')
    echo "SP key generated: $SP_ADDR"
else
    SP_ADDR=$(cast wallet address "$PRIVATE_KEY_SP" 2>/dev/null || echo "?")
    echo "SP key already set: $SP_ADDR"
fi

docker exec lotus lotus send "$DEFAULT_WALLET" 10000 2>/dev/null || true

echo "Keys saved to .env"
