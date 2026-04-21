#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST SP_REGISTRY

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")

echo "=== Register miners in SPRegistry ==="

# (actorId, retrievabilityBps, bandwidthMbps, latencyMs, indexingPct, availableGB, pricePerSectorPerMonth)
MINERS=(
    "$MINER_ACTOR_ID  10000  1000  100  100  1  0"
    "1001             8000   500   200  80   5  0"
    "1002             5000   100   500  50   10 100"
)

MIN_DEAL_DURATION_DAYS=1
MAX_DEAL_DURATION_DAYS=1278

register_miner() {
    local id="$1" retr="$2" bw="$3" lat="$4" idx="$5" gb="$6" price="$7"
    local avail=$(( gb * 1024 * 1024 * 1024 ))

    echo "Registering miner $id (retr=${retr}bps bw=${bw}mbps lat=${lat}ms idx=${idx}%)"
    csend \
        "$SP_REGISTRY" \
        "registerProviderFor(uint64,address,(uint16,uint16,uint16,uint8),uint256,uint256,address,uint32,uint32)" \
        "$id" "$DEPLOYER" "($retr,$bw,$lat,$idx)" "$avail" "$price" "$DEPLOYER" "$MIN_DEAL_DURATION_DAYS" "$MAX_DEAL_DURATION_DAYS"

    local registered
    registered=$(cast call --rpc-url "$RPC_URL" "$SP_REGISTRY" \
        "isProviderRegistered(uint64)(bool)" "$id" 2>/dev/null || echo "?")
    echo "  registered: $registered"
    [ "$registered" = "true" ] || { echo "ERROR: miner $id was not registered"; exit 1; }
}

for m in "${MINERS[@]}"; do
    # shellcheck disable=SC2086
    register_miner $m
done

echo "Done."
