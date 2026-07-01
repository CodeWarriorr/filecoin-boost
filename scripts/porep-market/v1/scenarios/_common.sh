#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common.sh"

fail() {
    echo "ERROR: $*"
    exit 1
}

assert_eq() {
    local actual="$1" expected="$2" msg="$3"
    [ "$actual" = "$expected" ] || fail "$msg (actual=$actual expected=$expected)"
}

assert_gt() {
    local actual="$1" threshold="$2" msg="$3"
    [ "$actual" -gt "$threshold" ] || fail "$msg (actual=$actual threshold=$threshold)"
}

assert_ge() {
    local actual="$1" threshold="$2" msg="$3"
    [ "$actual" -ge "$threshold" ] || fail "$msg (actual=$actual threshold=$threshold)"
}

assert_le() {
    local actual="$1" threshold="$2" msg="$3"
    [ "$actual" -le "$threshold" ] || fail "$msg (actual=$actual threshold=$threshold)"
}

assert_tx_reverted() {
    local tx_hash="$1" msg="$2"
    [ -n "$tx_hash" ] || fail "$msg (missing tx hash)"
    if wait_for_tx "$tx_hash" >/dev/null 2>&1; then
        fail "$msg (tx unexpectedly succeeded: $tx_hash)"
    fi
}

canon_addr() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

erc20_balance() {
    cast call --rpc-url "$RPC_URL" "$USDC_TOKEN" "balanceOf(address)(uint256)" "$1" | awk '{print $1}'
}

set_sli() {
    local retr="$1" bw="$2" lat="$3" idx="$4"
    require_env SLI_ORACLE
    echo "=== Update SLI ==="
    echo "  retrievabilityBps=$retr bandwidthMbps=$bw latencyMs=$lat indexingPct=$idx"
    csend "$SLI_ORACLE" "setSLI(uint64,(uint16,uint16,uint16,uint8))" "$MINER_ID" "($retr,$bw,$lat,$idx)"
}

settle_to_epoch() {
    local rail_id="$1" target_epoch="$2"
    local sp_before sp_after settled_before settled_after tx_hash delta
    sp_before=$(fp_balance "$SP_WALLET")
    settled_before=$(rail_settled_up_to "$rail_id")
    tx_hash=$(send_tx_hash "$FILECOIN_PAY" "settleRail(uint256,uint256)" "$rail_id" "$target_epoch")
    wait_for_tx "$tx_hash"
    sp_after=$(fp_balance "$SP_WALLET")
    settled_after=$(rail_settled_up_to "$rail_id")
    delta=$((sp_after - sp_before))
    printf '%s %s %s\n' "$delta" "$settled_before" "$settled_after"
}

settle_to_now() {
    local rail_id="$1"
    local target
    target=$(cast block-number --rpc-url "$RPC_URL")
    settle_to_epoch "$rail_id" "$target"
}

settle_with_accounting_to_epoch() {
    local rail_id="$1" target_epoch="$2"
    local client_before client_after sp_before sp_after settled_before settled_after tx_hash
    state_require DEPLOYER SP_WALLET
    client_before=$(fp_balance "$DEPLOYER")
    sp_before=$(fp_balance "$SP_WALLET")
    settled_before=$(rail_settled_up_to "$rail_id")
    tx_hash=$(send_tx_hash "$FILECOIN_PAY" "settleRail(uint256,uint256)" "$rail_id" "$target_epoch")
    wait_for_tx "$tx_hash"
    client_after=$(fp_balance "$DEPLOYER")
    sp_after=$(fp_balance "$SP_WALLET")
    settled_after=$(rail_settled_up_to "$rail_id")
    printf '%s %s %s %s\n' \
        "$((client_after - client_before))" \
        "$((sp_after - sp_before))" \
        "$settled_before" \
        "$settled_after"
}

settle_with_accounting_to_now() {
    local rail_id="$1"
    local target
    target=$(cast block-number --rpc-url "$RPC_URL")
    settle_with_accounting_to_epoch "$rail_id" "$target"
}
