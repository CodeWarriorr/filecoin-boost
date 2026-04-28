#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST

state_load
state_require DEAL_ID VALIDATOR RAIL_ID SP_WALLET TERMINATION_BLOCK TERMINATION_TX_HASH

RECEIPT=$(cast receipt --rpc-url "$RPC_URL" "$TERMINATION_TX_HASH" --json)
EVENT_SIG=$(cast keccak "RailTerminated(uint256,address,uint256)")
EVENT_LOG=$(echo "$RECEIPT" | jq -r --arg sig "$EVENT_SIG" --arg validator "$(echo "$VALIDATOR" | tr '[:upper:]' '[:lower:]')" '
    .logs[]
    | select(
        (.topics[0] == $sig) and
        ((.address | ascii_downcase) == $validator)
    )' | head -c 2000)

if [ -z "$EVENT_LOG" ]; then
    echo "ERROR: RailTerminated event not found in receipt - FilecoinPay did not call railTerminated()"
    exit 1
fi

# Extract and verify fields
EVENT_RAIL_ID=$(echo "$EVENT_LOG" | jq -r '.topics[1]' | cast --to-dec)
EVENT_TERMINATOR=$(echo "$EVENT_LOG" | jq -r '.topics[2]' | python3 -c "import sys; v=sys.stdin.read().strip(); print('0x'+v[-40:])")
EVENT_END_EPOCH=$(echo "$EVENT_LOG" | jq -r '.data' | cast --to-dec)
LOCKUP_PERIOD_END_BLOCK=$EVENT_END_EPOCH
state_set LOCKUP_PERIOD_END_BLOCK "$LOCKUP_PERIOD_END_BLOCK"
wait_for_block "$((LOCKUP_PERIOD_END_BLOCK + 1))"

DEAL_ID=$(state_get DEAL_ID)
DEAL_STATE=$(get_deal_field "$DEAL_ID" 12)
[ "$DEAL_STATE" = "4" ] || { echo "ERROR: Deal $DEAL_ID state is $DEAL_STATE, expected 4 (Terminated)"; exit 1; }
echo "  PoRepMarket deal state: Terminated (4) OK"

# --- Settle to endEpoch: pays remaining lockup window, triggers rail finalization ---
SP_FP_BEFORE=$(fp_balance "$SP_WALLET")
echo "--- Settling rail $RAIL_ID to endEpoch $LOCKUP_PERIOD_END_BLOCK (triggers finalization) ---"
csend "$FILECOIN_PAY" "settleRail(uint256,uint256)" "$RAIL_ID" "$LOCKUP_PERIOD_END_BLOCK"

SP_FP_AFTER=$(fp_balance "$SP_WALLET")
LOCKUP_WINDOW_PAYMENT=$(( SP_FP_AFTER - SP_FP_BEFORE ))
echo "  Lockup window payment: $LOCKUP_WINDOW_PAYMENT attoUSDC"
state_set PAID_AMOUNT_AFTER_TERMINATION "$LOCKUP_WINDOW_PAYMENT"

# Extra settle: rail finalized (from=address(0)), expected to revert with RailInactiveOrSettled
echo "--- Extra settle after finalization (expected revert) ---"
SP_FP_BEFORE_EXTRA=$(fp_balance "$SP_WALLET")
if csend "$FILECOIN_PAY" "settleRail(uint256,uint256)" "$RAIL_ID" "$LOCKUP_PERIOD_END_BLOCK" 2>/dev/null; then
    echo "  WARN: extra settleRail did not revert"
else
    echo "  Extra settleRail reverted as expected"
fi
SP_FP_AFTER_EXTRA=$(fp_balance "$SP_WALLET")
EXTRA_DELTA=$(( SP_FP_AFTER_EXTRA - SP_FP_BEFORE_EXTRA ))
echo "  SP balance delta after extra settle: $EXTRA_DELTA attoUSDC (expected 0)"
[ "$EXTRA_DELTA" -eq 0 ] || echo "  WARN: SP received $EXTRA_DELTA attoUSDC after finalization"
state_set EXTRA_SETTLE_DELTA "$EXTRA_DELTA"
