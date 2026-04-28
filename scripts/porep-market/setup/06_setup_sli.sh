#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST SLI_ORACLE

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")
echo "=== Set SLI Attestations ==="
echo "Deployer (ORACLE_ROLE): $DEPLOYER"

MINERS=(
    "1000  10000  1000  100  100"
    "1001  8000   500   200  80"
    "1002  5000   100   500  50"
)

for m in "${MINERS[@]}"; do
    read -r id retr bw lat idx <<< "$m"
    echo "Setting SLI for miner $id (retr=${retr}bps bw=${bw}mbps lat=${lat}ms idx=${idx}%)"
    csend "$SLI_ORACLE" "setSLI(uint64,(uint16,uint16,uint16,uint8))" "$id" "($retr,$bw,$lat,$idx)"
done

echo "Done."
