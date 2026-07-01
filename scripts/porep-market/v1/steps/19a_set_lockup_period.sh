#!/bin/bash
# Sets the lockup period on the validator contract.
# Env params:
#   LOCKUP_PERIOD_BLOCKS - lockup period in blocks (default: 5)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST

state_load
state_require VALIDATOR RAIL_ID

LOCKUP_PERIOD_BLOCKS="${1:-${LOCKUP_PERIOD_BLOCKS:-5}}"

echo "=== Set Lockup Period ==="
echo "  Validator:     $VALIDATOR"
echo "  Lockup period: $LOCKUP_PERIOD_BLOCKS blocks"

csend "$VALIDATOR" "updateLockupPeriod(uint256,uint256)" "$RAIL_ID" "$LOCKUP_PERIOD_BLOCKS"

echo "=== Lockup period updated to $LOCKUP_PERIOD_BLOCKS ==="
