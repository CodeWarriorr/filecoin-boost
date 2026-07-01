#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST SP_REGISTRY

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")

echo "=== Register V2 provider in SPRegistry ==="
echo "Current PoRep Market main has no createOffer or setPaymentToken API; V2 matching is provider price/capacity based."

MINER_ID="${MINER_ACTOR_ID:-1000}"
RETRIEVABILITY_BPS="${V2_RETRIEVABILITY_BPS:-10000}"
BANDWIDTH_BYTES_PER_SECOND="${V2_BANDWIDTH_BYTES_PER_SECOND:-1048576}"
LATENCY_MS="${V2_LATENCY_MS:-100}"
INDEXING_PCT="${V2_INDEXING_PCT:-100}"
AVAILABLE_BYTES="${V2_AVAILABLE_BYTES:-1073741824}"
PRICE_PER_32GIB_MONTH="${V2_PRICE_PER_32GIB_MONTH:-86400000000}"
MIN_DEAL_DURATION_DAYS="${V2_MIN_DEAL_DURATION_DAYS:-180}"
MAX_DEAL_DURATION_DAYS="${V2_MAX_DEAL_DURATION_DAYS:-1278}"

if cast call --rpc-url "$RPC_URL" "$SP_REGISTRY" "isProviderRegistered(uint64)(bool)" "$MINER_ID" 2>/dev/null | grep -q true; then
    echo "Provider $MINER_ID already registered, refreshing V2 smoke-test config"
    csend \
        "$SP_REGISTRY" \
        "setCapabilities(uint64,(uint16,uint64,uint16,uint8))" \
        "$MINER_ID" \
        "($RETRIEVABILITY_BPS,$BANDWIDTH_BYTES_PER_SECOND,$LATENCY_MS,$INDEXING_PCT)"
    csend "$SP_REGISTRY" "updateAvailableSpace(uint64,uint256)" "$MINER_ID" "$AVAILABLE_BYTES"
    csend "$SP_REGISTRY" "setPrice(uint64,uint256)" "$MINER_ID" "$PRICE_PER_32GIB_MONTH"
    csend "$SP_REGISTRY" "setPayee(uint64,address)" "$MINER_ID" "$DEPLOYER"
    csend "$SP_REGISTRY" "setDealDurationLimits(uint64,uint32,uint32)" \
        "$MINER_ID" "$MIN_DEAL_DURATION_DAYS" "$MAX_DEAL_DURATION_DAYS"
else
    csend \
        "$SP_REGISTRY" \
        "registerProviderFor(uint64,address,(uint16,uint64,uint16,uint8),uint256,uint256,address,uint32,uint32)" \
        "$MINER_ID" \
        "$DEPLOYER" \
        "($RETRIEVABILITY_BPS,$BANDWIDTH_BYTES_PER_SECOND,$LATENCY_MS,$INDEXING_PCT)" \
        "$AVAILABLE_BYTES" \
        "$PRICE_PER_32GIB_MONTH" \
        "$DEPLOYER" \
        "$MIN_DEAL_DURATION_DAYS" \
        "$MAX_DEAL_DURATION_DAYS"
fi

registered=$(cast call --rpc-url "$RPC_URL" "$SP_REGISTRY" "isProviderRegistered(uint64)(bool)" "$MINER_ID")
[ "$registered" = "true" ] || { echo "ERROR: provider $MINER_ID was not registered"; exit 1; }

state_set PROVIDER "$MINER_ID"
echo "Provider $MINER_ID registered for V2 auto-approval at price $PRICE_PER_32GIB_MONTH."
