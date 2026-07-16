#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet

state_load
state_require ALLOC_ID PIECE_CID PIECE_CAR_PATH

if [ -n "${CLIENT_FIL_ADDR:-}" ]; then
    CLIENT_F4="$CLIENT_FIL_ADDR"
else
    CLIENT_F4=$(docker exec lotus lotus evm stat "$DATACAP_EVIDENCE_ADAPTER" \
        | awk '/Filecoin address:/{print $3}' | tr -d '\r\n')
    [ -n "$CLIENT_F4" ] || { echo "ERROR: could not resolve adapter f4 address"; exit 1; }
fi

FULLNODE_API=$(docker exec lotus lotus auth api-info --perm=admin | cut -d= -f2-)
[ -n "$FULLNODE_API" ] || { echo "ERROR: could not get FULLNODE_API_INFO from lotus"; exit 1; }

HEAD_EPOCH=$(docker exec lotus lotus chain head --height | tr -d '\r\n ')
START_EPOCH_OFFSET="${DIRECT_IMPORT_START_EPOCH_OFFSET:-55}"
START_EPOCH=$((HEAD_EPOCH + START_EPOCH_OFFSET))
state_set DIRECT_IMPORT_START_EPOCH "$START_EPOCH"

echo "=== Import V2 piece ==="
echo "  Allocation: $ALLOC_ID"
echo "  Client:     $CLIENT_F4"
echo "  Piece CID:  $PIECE_CID"
echo "  Start epoch: $START_EPOCH (head $HEAD_EPOCH + $START_EPOCH_OFFSET)"

run_import_direct() {
    local output status
    set +e
    output=$(docker exec -e FULLNODE_API_INFO="$FULLNODE_API" boost boostd import-direct \
        --client-addr="$CLIENT_F4" \
        --allocation-id="$ALLOC_ID" \
        --start-epoch="$START_EPOCH" \
        "$PIECE_CID" "$PIECE_CAR_PATH" 2>&1)
    status=$?
    set -e
    printf '%s\n' "$output"
    if [ "$status" -ne 0 ] || printf '%s\n' "$output" | rg -q '(^Error:|API not running|could not get API info)'; then
        return 1
    fi
}

run_import_direct || {
    echo "  WARN: retrying import-direct in 30s"
    sleep 30
    HEAD_EPOCH=$(docker exec lotus lotus chain head --height | tr -d '\r\n ')
    START_EPOCH=$((HEAD_EPOCH + START_EPOCH_OFFSET))
    state_set DIRECT_IMPORT_START_EPOCH "$START_EPOCH"
    run_import_direct || { echo "ERROR: import-direct failed"; exit 1; }
}

echo "=== V2 piece imported ==="
