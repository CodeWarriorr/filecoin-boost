#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST SP_REGISTRY USDC_TOKEN

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")

echo "=== Register provider offer in SPRegistry ==="

PROVIDER="${MINER_ACTOR_ID:-1000}"
AVAILABLE_BYTES="${V2_AVAILABLE_BYTES:-1073741824}"
PRICE_PER_32GIB_MONTH="${V2_PRICE_PER_32GIB_MONTH:-86400000000}"
RETRIEVABILITY_BPS="${V2_RETRIEVABILITY_BPS:-10000}"
BANDWIDTH_BYTES_PER_SECOND="${V2_BANDWIDTH_BYTES_PER_SECOND:-1048576}"
LATENCY_MS="${V2_LATENCY_MS:-100}"
INDEXING_PCT="${V2_INDEXING_PCT:-100}"

REGISTERED=$(ccall "$SP_REGISTRY" "isProviderRegistered(uint64)(bool)" "$PROVIDER" 2>/dev/null || echo "false")

if [ "$REGISTERED" != "true" ]; then
    echo "Registering provider $PROVIDER"
    csend \
        "$SP_REGISTRY" \
        "registerProviderFor(uint64,address,uint256,address)" \
        "$PROVIDER" "$DEPLOYER" "$AVAILABLE_BYTES" "$DEPLOYER"
else
    echo "Provider $PROVIDER already registered"
    csend \
        "$SP_REGISTRY" \
        "updateAvailableSpace(uint64,uint256)" \
        "$PROVIDER" "$AVAILABLE_BYTES"
fi

echo "Allowing USDC payment token"
csend \
    "$SP_REGISTRY" \
    "setPaymentToken(address,bool,uint256)" \
    "$USDC_TOKEN" true 1

OFFERS=$(ccall "$SP_REGISTRY" "getOffersByProvider(uint64)(uint256[])" "$PROVIDER" 2>/dev/null || echo "[]")
OFFER_ID=$(printf '%s\n' "$OFFERS" | grep -Eo '[0-9]+' | head -1 || true)

if [ -z "$OFFER_ID" ]; then
    echo "Creating provider offer"
    csend \
        "$SP_REGISTRY" \
        "createOffer(uint64,(uint256,uint256,uint64,uint64),(uint16,uint64,uint16,uint8),(address,bool,uint256)[])" \
        "$PROVIDER" \
        "(1,0,0,0)" \
        "($RETRIEVABILITY_BPS,$BANDWIDTH_BYTES_PER_SECOND,$LATENCY_MS,$INDEXING_PCT)" \
        "[($USDC_TOKEN,true,$PRICE_PER_32GIB_MONTH)]"
else
    echo "Provider offer already exists: $OFFER_ID"
    csend "$SP_REGISTRY" "setOfferActive(uint256,bool)" "$OFFER_ID" true
    csend "$SP_REGISTRY" "setOfferPayment(uint256,address,bool,uint256)" \
        "$OFFER_ID" "$USDC_TOKEN" true "$PRICE_PER_32GIB_MONTH"
fi

state_set PROVIDER "$PROVIDER"

echo "Done."
