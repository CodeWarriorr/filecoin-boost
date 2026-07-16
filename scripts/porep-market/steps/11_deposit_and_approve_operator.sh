#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
chain_id=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null || true)
[ "$chain_id" = "31415926" ] || {
    echo "ERROR: expected chain ID 31415926, got ${chain_id:-unavailable}" >&2
    exit 1
}
require_env PRIVATE_KEY_TEST FILECOIN_PAY USDC_TOKEN VALIDATOR_FACTORY

state_load
state_require DEAL_ID

DEPOSIT_AMOUNT_INPUT="${1:-1000}"

VALIDATOR_ADDR=$(cast call \
  --rpc-url "$RPC_URL" \
  "$VALIDATOR_FACTORY" \
  "getInstance(uint256)(address)" \
  "$DEAL_ID" | head -1)

if [ -z "$VALIDATOR_ADDR" ]; then
    echo "ERROR: Validator not found for deal ID $DEAL_ID"
    echo ""
    exit 1
fi

CLIENT_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY_TEST")
MAX_UINT256=$(cast max-uint uint256)

BALANCE=$(cast call \
  --rpc-url "$RPC_URL" \
  "$USDC_TOKEN" \
  "balanceOf(address)(uint256)" \
  "$CLIENT_ADDR" | awk '{print $1}')

read -r V R S DEPOSIT_AMOUNT PERMIT_DEADLINE < <(
  node "$SCRIPT_DIR/sign_permit.js" "$RPC_URL" "$PRIVATE_KEY_TEST" "$USDC_TOKEN" "$FILECOIN_PAY" "$DEPOSIT_AMOUNT_INPUT" \
  | jq -r '[.v, .r, .s, .amount, .deadline] | @tsv'
)

if node -e "process.exit(BigInt(process.argv[1]) < BigInt(process.argv[2]) ? 0 : 1)" "$BALANCE" "$DEPOSIT_AMOUNT"; then
    echo "ERROR: insufficient USDC — need $DEPOSIT_AMOUNT, have $BALANCE" >&2
    exit 1
fi

echo "=== TX6: Deposit + Operator Approval ==="
echo "  RPC=$RPC_URL  Client=$CLIENT_ADDR"
echo "  Deal ID=$DEAL_ID"
echo "  Validator=$VALIDATOR_ADDR"
echo "  Balance=$BALANCE"
echo "  MaxUint256=$MAX_UINT256"
echo "  Token=$USDC_TOKEN  FilecoinPay=$FILECOIN_PAY  Validator=$VALIDATOR_ADDR"
echo "  Amount=$DEPOSIT_AMOUNT  Deadline=$PERMIT_DEADLINE  Permit sig: v=$V r=$R s=$S"

RECEIPT=$(send_tx_output \
  "$FILECOIN_PAY" \
  "depositWithPermitAndApproveOperator(address,address,uint256,uint256,uint8,bytes32,bytes32,address,uint256,uint256,uint256)" \
  "$USDC_TOKEN" "$CLIENT_ADDR" "$DEPOSIT_AMOUNT" "$PERMIT_DEADLINE" "$V" "$R" "$S" "$VALIDATOR_ADDR" "$MAX_UINT256" "$MAX_UINT256" "$MAX_UINT256")

TX_HASH=$(extract_tx_hash "$RECEIPT")
STATUS=$(extract_status "$RECEIPT")

if [ "$STATUS" != "0x1" ]; then
    echo "ERROR: transaction reverted with status $STATUS" >&2
    exit 1
fi

echo "=== Transaction completed ==="
echo "  TX=$TX_HASH"
echo "  Status: $STATUS"

ACCT_FUNDS=$(cast call \
  --rpc-url "$RPC_URL" \
  "$FILECOIN_PAY" \
  "accounts(address,address)(uint256,uint256,uint256,uint256)" \
  "$USDC_TOKEN" "$CLIENT_ADDR" | head -1)

APPROVAL_RESULT=$(cast call \
  --rpc-url "$RPC_URL" \
  "$FILECOIN_PAY" \
  "operatorApprovals(address,address,address)(bool,uint256,uint256,uint256,uint256,uint256)" \
  "$USDC_TOKEN" "$CLIENT_ADDR" "$VALIDATOR_ADDR")

echo "  Funds=$ACCT_FUNDS  Approved=$(echo "$APPROVAL_RESULT" | sed -n '1p')  MaxLockup=$(echo "$APPROVAL_RESULT" | sed -n '6p')"

echo "TX6 complete"
