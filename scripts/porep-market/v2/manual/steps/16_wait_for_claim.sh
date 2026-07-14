#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet

state_load
state_require ALLOC_ID

MINER_ID="${MINER_ID:-1000}"
MINER_ACTOR="t0${MINER_ID}"
MAX_ATTEMPTS="${CLAIM_MAX_ATTEMPTS:-900}"
POLL_INTERVAL="${CLAIM_POLL_SECONDS:-1}"
TARGET_START_EPOCH="${DIRECT_IMPORT_START_EPOCH:-}"

echo "=== Wait for V2 claim ==="
echo "  Allocation: $ALLOC_ID"
echo "  Miner:      $MINER_ACTOR"

docker exec lotus-miner lotus-miner sectors batching precommit --publish-now 2>/dev/null || true

claim_exists() {
    docker exec lotus lotus filplus list-claims "$MINER_ACTOR" 2>/dev/null \
        | awk -v id="$ALLOC_ID" '$1 == id {found=1} END {exit !found}'
}

publish_batches() {
    docker exec lotus-miner lotus-miner sectors batching precommit --publish-now 2>/dev/null || true
    docker exec lotus-miner lotus-miner sectors batching commit --publish-now 2>/dev/null || true
}

CLAIM_FOUND=0
for i in $(seq 1 "$MAX_ATTEMPTS"); do
    if claim_exists; then
        CLAIM_FOUND=1
        echo "  Claim $ALLOC_ID confirmed on-chain"
        break
    fi

    if [ -n "$TARGET_START_EPOCH" ]; then
        HEAD_EPOCH=$(docker exec lotus lotus chain head --height 2>/dev/null | tr -d '\r\n ' || echo 0)
        if [ "$HEAD_EPOCH" -ge $((TARGET_START_EPOCH - 3)) ] && [ "$HEAD_EPOCH" -le $((TARGET_START_EPOCH + 3)) ]; then
            echo "  Target start epoch window: head=$HEAD_EPOCH target=$TARGET_START_EPOCH"
            while [ "$HEAD_EPOCH" -lt "$TARGET_START_EPOCH" ]; do
                sleep 0.1
                HEAD_EPOCH=$(docker exec lotus lotus chain head --height 2>/dev/null | tr -d '\r\n ' || echo 0)
            done
            docker exec lotus-miner lotus-miner sectors batching commit --publish-now 2>&1 || true
        else
            publish_batches
        fi
    else
        publish_batches
    fi

    if [ "$i" -eq 1 ] || [ $((i % 30)) -eq 0 ]; then
        echo "  [$i/$MAX_ATTEMPTS] waiting... (${POLL_INTERVAL}s)"
    fi
    sleep "$POLL_INTERVAL"
done

[ "$CLAIM_FOUND" -eq 1 ] || { echo "ERROR: claim $ALLOC_ID not found after $((MAX_ATTEMPTS * POLL_INTERVAL))s"; exit 1; }

echo "=== V2 claim confirmed ==="
