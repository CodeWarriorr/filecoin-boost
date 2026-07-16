#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POREP_MARKET_VERSION="${POREP_MARKET_VERSION:-v2}"
source "$SCRIPT_DIR/../$POREP_MARKET_VERSION/_common.sh"

require_devnet

chain_id=$(cast chain-id --rpc-url "$RPC_URL")
[ "$chain_id" = "31415926" ] || {
    echo "ERROR: expected chain ID 31415926, got $chain_id" >&2
    exit 1
}

case "$POREP_MARKET_VERSION" in
    v1)
        required_addresses=(
            POREP_MARKET CLIENT_CONTRACT SP_REGISTRY VALIDATOR_FACTORY
            FILECOIN_PAY SLI_ORACLE META_ALLOCATOR USDC_TOKEN
        )
        ;;
    v2)
        required_addresses=(
            POREP_MARKET DATACAP_EVIDENCE_ADAPTER SP_REGISTRY VALIDATOR_FACTORY
            FILECOIN_PAY SLI_ORACLE META_ALLOCATOR USDC_TOKEN
        )
        ;;
    *)
        echo "ERROR: unsupported POREP_MARKET_VERSION=$POREP_MARKET_VERSION" >&2
        exit 1
        ;;
esac

echo "RPC_URL=$RPC_URL"
echo "POREP_MARKET_VERSION=$POREP_MARKET_VERSION"
echo "POREP_DIR=$POREP_DIR"

for name in "${required_addresses[@]}"; do
    address="${!name:-}"
    [[ "$address" =~ ^0x[0-9a-fA-F]{40}$ ]] || {
        echo "ERROR: $name is not a valid EVM address" >&2
        exit 1
    }
    [[ "$address" != "0x0000000000000000000000000000000000000000" ]] || {
        echo "ERROR: $name is the zero address" >&2
        exit 1
    }
    code=$(cast code --rpc-url "$RPC_URL" "$address")
    [ -n "$code" ] && [ "$code" != "0x" ] || {
        echo "ERROR: $name has no bytecode" >&2
        exit 1
    }
    echo "$name=$address"
done
