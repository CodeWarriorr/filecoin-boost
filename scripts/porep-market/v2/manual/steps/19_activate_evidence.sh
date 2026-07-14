#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST POREP_MARKET FILECOIN_PAY USDC_TOKEN

state_load
state_require DEAL_ID RAIL_ID

echo "=== Activate V2 evidence ==="
echo "  Deal: $DEAL_ID"
echo "  Rail: $RAIL_ID"

TX_HASH=$(send_tx_hash "$POREP_MARKET" "activateEvidence(uint256,bytes)" "$DEAL_ID" "0x")
wait_for_tx "$TX_HASH"

STATE=$(get_v2_deal_field "$DEAL_ID" 4)
[ "$STATE" = "30" ] || { echo "ERROR: V2 deal $DEAL_ID state expected 30 (ACTIVE), got $STATE"; exit 1; }

CAPACITY_JSON=$(get_v2_deal_capacity_json "$DEAL_ID")
COMMITTED_BYTES=$(printf '%s\n' "$CAPACITY_JSON" | jq -r '.[0][1]')
[ "$COMMITTED_BYTES" -gt 0 ] || { echo "ERROR: committedBytes expected > 0, got $COMMITTED_BYTES"; exit 1; }

PAYMENT_RATE=$(rail_payment_rate "$RAIL_ID")
[ "$PAYMENT_RATE" -gt 0 ] || { echo "ERROR: rail payment rate expected > 0, got $PAYMENT_RATE"; exit 1; }

state_set DEAL_STATE "ACTIVE"
state_set COMMITTED_BYTES "$COMMITTED_BYTES"
state_set PAYMENT_RATE "$PAYMENT_RATE"

echo "  TX: $TX_HASH"
echo "  Deal state: ACTIVE"
echo "  Committed bytes: $COMMITTED_BYTES"
echo "  Rail payment rate: $PAYMENT_RATE"
echo "=== V2 evidence activated ==="
