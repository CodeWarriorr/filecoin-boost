#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST

VALIDATOR="${1:-}"
RAIL_ID="${2:-}"

if [ -z "$VALIDATOR" ] || [ -z "$RAIL_ID" ]; then
    echo "Usage: $0 <VALIDATOR_ADDRESS> <RAIL_ID>"
    echo "Example: $0 0xAbCd...1234 42"
    exit 1
fi

echo "Method:   terminateRail(uint256)"
echo "Caller:   $VALIDATOR"
echo "Rail ID:  $RAIL_ID"
echo ""

TX_HASH=$(send_tx_hash \
    "$VALIDATOR" \
    "terminateRail(uint256)" \
    "$RAIL_ID")

wait_for_tx "$TX_HASH"

echo "Done."
