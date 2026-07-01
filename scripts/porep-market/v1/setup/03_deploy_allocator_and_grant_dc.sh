#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST
require_env CLIENT_CONTRACT

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")
echo "Deployer: $DEPLOYER"

# Genesis root key holders must be present — lost if devnet data was not fully wiped on reset
ROOT_KEY_1=$(docker exec lotus cat /var/lib/lotus/rootkey-1 2>/dev/null | tr -d '\r\n')
ROOT_KEY_2=$(docker exec lotus cat /var/lib/lotus/rootkey-2 2>/dev/null | tr -d '\r\n')
[ -n "$ROOT_KEY_1" ] || { echo "ERROR: rootkey-1 not found in lotus container — is devnet fully initialized?"; exit 1; }
[ -n "$ROOT_KEY_2" ] || { echo "ERROR: rootkey-2 not found in lotus container — is devnet fully initialized?"; exit 1; }
docker exec lotus lotus wallet list 2>/dev/null | grep -q "$ROOT_KEY_1" || { echo "ERROR: root key $ROOT_KEY_1 not in lotus wallet — stale devnet data. Run 'make devnet/down && make devnet/up' to reset."; exit 1; }
docker exec lotus lotus wallet list 2>/dev/null | grep -q "$ROOT_KEY_2" || { echo "ERROR: root key $ROOT_KEY_2 not in lotus wallet — stale devnet data. Run 'make devnet/down && make devnet/up' to reset."; exit 1; }

# Fund deployer (idempotent)
docker exec lotus lotus send "$DEPLOYER" 10000 2>/dev/null || true
wait_for_tx

# Helper: propose add-verifier and approve the resulting msig TX.
# Captures TX count before proposal to reliably find the new TX.
propose_and_approve_verifier() {
    local addr="$1" amount="$2"

    # Snapshot current highest TX ID (may be empty on first call)
    local before_tx_id
    before_tx_id=$(docker exec lotus lotus msig inspect f080 | \
        awk '/^Transactions:/{flag=1; next} flag && /^[0-9]+/{print $1}' | sort -nr | head -n1)

    docker exec lotus lotus-shed verifreg add-verifier t0100 "$addr" "$amount"

    local new_tx_id
    new_tx_id=$(docker exec lotus lotus msig inspect f080 | \
        awk '/^Transactions:/{flag=1; next} flag && /^[0-9]+/{print $1}' | sort -nr | head -n1)

    if [ -n "$new_tx_id" ] && [ "$new_tx_id" != "${before_tx_id:-}" ]; then
        echo "  Approving msig tx $new_tx_id"
        docker exec lotus lotus msig approve --from t0101 f080 "$new_tx_id"
    else
        echo "  WARN: no new msig TX detected"
    fi
    wait_for_tx
}

# MetaAllocator is now deployed in 02_deploy.sh (required by Deploy.s.sol)
require_env META_ALLOCATOR

# ============================================================
# Phase 1: Make MetaAllocator a verifier (notary)
# ============================================================
echo "=== Phase 1: Register MetaAllocator as verifier ==="

META_FIL_ADDR=$(docker exec lotus lotus evm stat "$META_ALLOCATOR" \
    | awk '/Filecoin address:/{print $3}' | tr -d '\r\n')
echo "  MetaAllocator FIL addr: $META_FIL_ADDR"

propose_and_approve_verifier "$META_FIL_ADDR" 999999999999999999

echo "  Verifiers:"
docker exec lotus lotus filplus list-notaries

# ============================================================
# Phase 2: Grant allowance on MetaAllocator to deployer
# ============================================================
echo "=== Phase 2: Grant allowance to deployer on MetaAllocator ==="

csend "$META_ALLOCATOR" 'addAllowance(address,uint256)' "$DEPLOYER" 999999999999999999

echo "  Deployer allowance: $(cast call --rpc-url "$RPC_URL" \
    "$META_ALLOCATOR" 'allowance(address)(uint256)' "$DEPLOYER")"

echo "Granting allowance to Client contract on MetaAllocator..."
csend "$META_ALLOCATOR" 'addAllowance(address,uint256)' "$CLIENT_CONTRACT" 999999999999999999

echo "  Client allowance: $(cast call --rpc-url "$RPC_URL" \
    "$META_ALLOCATOR" 'allowance(address)(uint256)' "$CLIENT_CONTRACT")"

# ============================================================
# Phase 3: Grant datacap to Client.sol via MetaAllocator
# ============================================================
echo "=== Phase 3: Grant datacap to Client via addVerifiedClient ==="

# Build f4 address bytes: 0x04 (protocol 4) + 0x0a (EAM id=10) + 20-byte eth addr
CLIENT_LOWER=$(echo "$CLIENT_CONTRACT" | tr '[:upper:]' '[:lower:]')
CLIENT_FIL_BYTES="0x040a${CLIENT_LOWER#0x}"
echo "  Client f4 bytes: $CLIENT_FIL_BYTES"

csend "$META_ALLOCATOR" 'addVerifiedClient(bytes,uint256)' "$CLIENT_FIL_BYTES" 99999999999999

CLIENT_FIL_ADDR=$(docker exec lotus lotus evm stat "$CLIENT_CONTRACT" \
    | awk '/Filecoin address:/{print $3}' | tr -d '\r\n')
echo "  Client FIL addr: $CLIENT_FIL_ADDR"
update_env "CLIENT_FIL_ADDR" "$CLIENT_FIL_ADDR"

echo "  Verifying datacap via MetaAllocator..."
docker exec lotus lotus filplus check-client-datacap "$CLIENT_FIL_ADDR" || true

echo "  Final datacap check:"
docker exec lotus lotus filplus check-client-datacap "$CLIENT_FIL_ADDR"

echo "Done."
