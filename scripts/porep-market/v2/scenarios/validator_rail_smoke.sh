#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/_common.sh"

STATE_FILE=${1:-"/tmp/porep-v2-validator-rail-smoke-$$.state"}
STATE_DIR="$(cd "$(dirname "$STATE_FILE")" && pwd)"
STATE_FILE="$STATE_DIR/$(basename "$STATE_FILE")"
export STATE_FILE
echo "State: $STATE_FILE"

bash "$SETUP/04_register_provider_and_offer.sh"
bash "$STEPS/07_propose_deal.sh"
bash "$STEPS/10_deploy_validator.sh"
bash "$STEPS/11_deposit_and_approve_operator.sh" "${V2_DEPOSIT_AMOUNT:-1000}"
bash "$STEPS/12_create_rail.sh"

state_require DEAL_ID VALIDATOR RAIL_ID

echo "RESULT: V2 validator and prepared rail smoke verified deal $DEAL_ID, validator $VALIDATOR, rail $RAIL_ID."
