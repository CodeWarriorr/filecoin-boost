#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST

state_load

VALIDATOR="${1:-$(state_get VALIDATOR)}"
RAIL_ID="${2:-$(state_get RAIL_ID)}"

[ -n "$VALIDATOR" ] || { echo "ERROR: VALIDATOR required (arg or state)"; exit 1; }
[ -n "$RAIL_ID" ] || { echo "ERROR: RAIL_ID required (arg or state)"; exit 1; }

echo "Method:   modifyRailPayment(uint256)"
echo "Validator: $VALIDATOR"
echo "Rail ID:  $RAIL_ID"

csend "$VALIDATOR" "modifyRailPayment(uint256)" "$RAIL_ID"

echo "Done."
