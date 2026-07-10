#!/bin/bash
# Env params (all optional):
#   EVIDENCE_BATCH_SIZE - number of allocation/claim ids to check (default: 1)
#   SETTLE_WAIT         - seconds to wait for blocks to advance (default: 60)
# State in: DEAL_ID, VALIDATOR, RAIL_ID
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST POREP_MARKET SLI_ORACLE

state_load
state_require DEAL_ID VALIDATOR RAIL_ID

CURRENT_BLOCK=$(cast block-number --rpc-url "$RPC_URL")
SETTLE_WAIT="${SETTLE_WAIT:-60}"
MIN_INTERVAL="${MIN_INTERVAL:-1}"
EVIDENCE_BATCH_SIZE="${EVIDENCE_BATCH_SIZE:-1}"
EVIDENCE_DATA=$(cast abi-encode "x(uint256)" "$EVIDENCE_BATCH_SIZE")

state_set ACTIVATION_BLOCK "$CURRENT_BLOCK"
state_set ACTIVATION_MIN_INTERVAL "$MIN_INTERVAL"

echo "=== Activate Payment ==="
echo "  Deal:      $DEAL_ID"
echo "  Validator: $VALIDATOR"
echo "  Rail:      $RAIL_ID"
echo "  Evidence batch size: $EVIDENCE_BATCH_SIZE"
echo "  Min settlement interval: $MIN_INTERVAL"

TX_HASH=$(send_tx_hash \
    "$POREP_MARKET" \
    "submitEvidenceBatch(uint256,bytes)" "$DEAL_ID" "$EVIDENCE_DATA")
wait_for_tx "$TX_HASH"
echo "  evidence batch submitted"

TX_HASH=$(send_tx_hash \
    "$POREP_MARKET" \
    "activateEvidence(uint256,bytes)" "$DEAL_ID" "0x")
wait_for_tx "$TX_HASH"
echo "  evidence activated and payment started"

TX_HASH=$(send_tx_hash \
    "$POREP_MARKET" \
    "setMinEpochsBetweenSettlements(uint256,uint256)" "$DEAL_ID" "$MIN_INTERVAL")
wait_for_tx "$TX_HASH"
echo "  settlement interval set"

SLI_RETR=$(get_deal_field "$DEAL_ID" 4)
SLI_BW=$(get_deal_field "$DEAL_ID" 5)
SLI_LAT=$(get_deal_field "$DEAL_ID" 6)
SLI_IDX=$(get_deal_field "$DEAL_ID" 7)
TX_HASH=$(send_tx_hash \
    "$SLI_ORACLE" \
    "setSLI(uint256,(uint16,uint64,uint16,uint8))" "$DEAL_ID" "($SLI_RETR,$SLI_BW,$SLI_LAT,$SLI_IDX)")
wait_for_tx "$TX_HASH"
echo "  SLI attestation set"

TX_HASH=$(send_tx_hash \
    "$POREP_MARKET" \
    "refreshEvidenceStatus(uint256,bytes)" "$DEAL_ID" "$EVIDENCE_DATA")
wait_for_tx "$TX_HASH"
echo "  evidence status refreshed"

echo "  Waiting ${SETTLE_WAIT}s for blocks to advance..."
sleep "$SETTLE_WAIT"

echo "=== Payment activated ==="
