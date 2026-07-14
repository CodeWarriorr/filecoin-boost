#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST META_ALLOCATOR DATACAP_EVIDENCE_ADAPTER

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")
DATACAP_ALLOWANCE="${V2_DATACAP_ALLOWANCE:-999999999999999999}"

echo "=== Grant V2 DataCap authority ==="
echo "Deployer: $DEPLOYER"
echo "MetaAllocator: $META_ALLOCATOR"
echo "DataCapEvidenceAdapter: $DATACAP_EVIDENCE_ADAPTER"

ROOT_KEY_1=$(docker exec lotus cat /var/lib/lotus/rootkey-1 2>/dev/null | tr -d '\r\n')
ROOT_KEY_2=$(docker exec lotus cat /var/lib/lotus/rootkey-2 2>/dev/null | tr -d '\r\n')
[ -n "$ROOT_KEY_1" ] || { echo "ERROR: rootkey-1 not found in lotus container"; exit 1; }
[ -n "$ROOT_KEY_2" ] || { echo "ERROR: rootkey-2 not found in lotus container"; exit 1; }
docker exec lotus lotus wallet list 2>/dev/null | grep -q "$ROOT_KEY_1" || {
    echo "ERROR: root key $ROOT_KEY_1 not in lotus wallet; reset devnet data" >&2
    exit 1
}
docker exec lotus lotus wallet list 2>/dev/null | grep -q "$ROOT_KEY_2" || {
    echo "ERROR: root key $ROOT_KEY_2 not in lotus wallet; reset devnet data" >&2
    exit 1
}

docker exec lotus lotus send "$DEPLOYER" 10000 2>/dev/null || true
wait_for_tx

propose_and_approve_verifier() {
    local addr="$1" amount="$2"
    local before_tx_id new_tx_id

    before_tx_id=$(docker exec lotus lotus msig inspect f080 \
        | awk '/^Transactions:/{flag=1; next} flag && /^[0-9]+/{print $1}' \
        | sort -nr | head -n1)

    docker exec lotus lotus-shed verifreg add-verifier t0100 "$addr" "$amount"

    new_tx_id=$(docker exec lotus lotus msig inspect f080 \
        | awk '/^Transactions:/{flag=1; next} flag && /^[0-9]+/{print $1}' \
        | sort -nr | head -n1)

    if [ -n "$new_tx_id" ] && [ "$new_tx_id" != "${before_tx_id:-}" ]; then
        echo "Approving msig tx $new_tx_id"
        docker exec lotus lotus msig approve --from t0101 f080 "$new_tx_id"
    else
        echo "WARN: no new msig TX detected"
    fi
    wait_for_tx
}

META_FIL_ADDR=$(docker exec lotus lotus evm stat "$META_ALLOCATOR" \
    | awk '/Filecoin address:/{print $3}' | tr -d '\r\n')
[ -n "$META_FIL_ADDR" ] || { echo "ERROR: could not resolve MetaAllocator Filecoin address"; exit 1; }
echo "MetaAllocator FIL addr: $META_FIL_ADDR"

propose_and_approve_verifier "$META_FIL_ADDR" "$DATACAP_ALLOWANCE"

echo "Granting MetaAllocator allowance to adapter..."
csend "$META_ALLOCATOR" 'addAllowance(address,uint256)' "$DATACAP_EVIDENCE_ADAPTER" "$DATACAP_ALLOWANCE"

ADAPTER_ALLOWANCE=$(cast call --rpc-url "$RPC_URL" \
    "$META_ALLOCATOR" 'allowance(address)(uint256)' "$DATACAP_EVIDENCE_ADAPTER")
[ "$ADAPTER_ALLOWANCE" != "0" ] || { echo "ERROR: adapter MetaAllocator allowance is zero"; exit 1; }

echo "Adapter allowance: $ADAPTER_ALLOWANCE"
echo "=== V2 DataCap authority ready ==="
