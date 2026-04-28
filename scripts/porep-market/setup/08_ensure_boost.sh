#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet

echo "=== Ensure Boost ==="

START_EPOCH_SEALING_BUFFER="${BOOST_DIRECT_START_EPOCH_SEALING_BUFFER:-20}"
BOOST_BUFFER_MARKER="/var/lib/boost/.porep-start-buffer-${START_EPOCH_SEALING_BUFFER}"
MINER_BUFFER_MARKER="/var/lib/lotus-miner/.porep-sealing-fast-${START_EPOCH_SEALING_BUFFER}"

if ! docker exec lotus-miner test -f "$MINER_BUFFER_MARKER" 2>/dev/null; then
    docker exec lotus-miner bash -c "
        set -e
        if grep -q '^[[:space:]]*#StartEpochSealingBuffer' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*#StartEpochSealingBuffer = .*/  StartEpochSealingBuffer = ${START_EPOCH_SEALING_BUFFER}/' /var/lib/lotus-miner/config.toml
        elif grep -q '^[[:space:]]*StartEpochSealingBuffer' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*StartEpochSealingBuffer = .*/  StartEpochSealingBuffer = ${START_EPOCH_SEALING_BUFFER}/' /var/lib/lotus-miner/config.toml
        else
            sed -i '/^\\[Sealing\\]/a\\  StartEpochSealingBuffer = ${START_EPOCH_SEALING_BUFFER}' /var/lib/lotus-miner/config.toml
        fi
        if grep -q '^[[:space:]]*#AggregateCommits' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*#AggregateCommits = .*/  AggregateCommits = false/' /var/lib/lotus-miner/config.toml
        elif grep -q '^[[:space:]]*AggregateCommits' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*AggregateCommits = .*/  AggregateCommits = false/' /var/lib/lotus-miner/config.toml
        else
            sed -i '/^\\[Sealing\\]/a\\  AggregateCommits = false' /var/lib/lotus-miner/config.toml
        fi
        if grep -q '^[[:space:]]*#MinCommitBatch' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*#MinCommitBatch = .*/  MinCommitBatch = 1/' /var/lib/lotus-miner/config.toml
        elif grep -q '^[[:space:]]*MinCommitBatch' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*MinCommitBatch = .*/  MinCommitBatch = 1/' /var/lib/lotus-miner/config.toml
        else
            sed -i '/^\\[Sealing\\]/a\\  MinCommitBatch = 1' /var/lib/lotus-miner/config.toml
        fi
        if grep -q '^[[:space:]]*#MaxCommitBatch' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*#MaxCommitBatch = .*/  MaxCommitBatch = 1/' /var/lib/lotus-miner/config.toml
        elif grep -q '^[[:space:]]*MaxCommitBatch' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*MaxCommitBatch = .*/  MaxCommitBatch = 1/' /var/lib/lotus-miner/config.toml
        else
            sed -i '/^\\[Sealing\\]/a\\  MaxCommitBatch = 1' /var/lib/lotus-miner/config.toml
        fi
        if grep -q '^[[:space:]]*#CommitBatchWait' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*#CommitBatchWait = .*/  CommitBatchWait = \"1s\"/' /var/lib/lotus-miner/config.toml
        elif grep -q '^[[:space:]]*CommitBatchWait' /var/lib/lotus-miner/config.toml; then
            sed -i 's/^[[:space:]]*CommitBatchWait = .*/  CommitBatchWait = \"1s\"/' /var/lib/lotus-miner/config.toml
        else
            sed -i '/^\\[Sealing\\]/a\\  CommitBatchWait = \"1s\"' /var/lib/lotus-miner/config.toml
        fi
        rm -f /var/lib/lotus-miner/.porep-start-buffer-* /var/lib/lotus-miner/.porep-sealing-fast-*
        touch '$MINER_BUFFER_MARKER'
    " 2>/dev/null || true
    docker restart lotus-miner >/dev/null
    sleep 10
    docker exec lotus-miner lotus-miner wait-api >/dev/null
fi

if ! docker exec boost test -f "$BOOST_BUFFER_MARKER" 2>/dev/null; then
    docker exec boost bash -c "
        set -e
        if grep -q '^[[:space:]]*#StartEpochSealingBuffer' /var/lib/boost/config.toml; then
            sed -i 's/^[[:space:]]*#StartEpochSealingBuffer = .*/  StartEpochSealingBuffer = ${START_EPOCH_SEALING_BUFFER}/' /var/lib/boost/config.toml
        elif grep -q '^[[:space:]]*StartEpochSealingBuffer' /var/lib/boost/config.toml; then
            sed -i 's/^[[:space:]]*StartEpochSealingBuffer = .*/  StartEpochSealingBuffer = ${START_EPOCH_SEALING_BUFFER}/' /var/lib/boost/config.toml
        else
            sed -i '/^\\[Dealmaking\\]/a\\  StartEpochSealingBuffer = ${START_EPOCH_SEALING_BUFFER}' /var/lib/boost/config.toml
        fi
        rm -f /var/lib/boost/.porep-start-buffer-*
        touch '$BOOST_BUFFER_MARKER'
        pkill -x boostd || pkill -f 'boostd' || true
        rm -f /var/lib/boost/api
    " 2>/dev/null || true
    sleep 5
fi

if ! docker exec boost curl -s http://localhost:8044 > /dev/null 2>&1; then
    docker exec -d boost bash -c \
        'boostd-data -vv run yugabyte --hosts yugabytedb --connect-string="postgresql://yugabyte:yugabyte@yugabytedb:5433?sslmode=disable" --addr 0.0.0.0:8044 &>/var/lib/boost/boostd-data.log' 2>/dev/null || true
    sleep 10
fi

if ! docker exec boost ls /var/lib/boost/api 2>/dev/null; then
    FULLNODE_API=$(docker exec lotus lotus auth api-info --perm=admin 2>/dev/null | cut -d= -f2-)
    docker exec -d boost bash -c \
        "export FULLNODE_API_INFO='$FULLNODE_API' && exec boostd -vv run --nosync=true --deprecated=true >> /var/lib/boost/boostd.log 2>&1" 2>/dev/null || true
    sleep 25
fi

echo "  Boost ready"
echo "=== Boost OK ==="
