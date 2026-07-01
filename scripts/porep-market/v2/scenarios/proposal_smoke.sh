#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/_common.sh"

STATE_FILE=${1:-"/tmp/porep-v2-proposal-smoke-$$.state"}
STATE_DIR="$(cd "$(dirname "$STATE_FILE")" && pwd)"
STATE_FILE="$STATE_DIR/$(basename "$STATE_FILE")"
export STATE_FILE
echo "State: $STATE_FILE"

bash "$SETUP/04_register_provider_and_offer.sh"
bash "$STEPS/07_propose_deal.sh"

state_require DEAL_ID
state_load

echo "RESULT: V2 proposal smoke verified deal $DEAL_ID in ACCEPTED state."
