#!/bin/bash
# Params:
#   CLIENT_ACTOR       - client contract Filecoin address (default: t01098)
# State in: ALLOC_ID, PIECE_CID, PIECE_CAR_PATH
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet

state_load
state_require ALLOC_ID PIECE_CID PIECE_CAR_PATH

if [ -n "${CLIENT_FIL_ADDR:-}" ]; then
    CLIENT_F4="$CLIENT_FIL_ADDR"
else
    CLIENT_ACTOR="${CLIENT_ACTOR:-t01098}"
    CLIENT_F4=$(docker exec lotus lotus state lookup -r "$CLIENT_ACTOR" 2>/dev/null || echo "")
    [ -n "$CLIENT_F4" ] || { echo "ERROR: Could not resolve client f4 address for $CLIENT_ACTOR"; exit 1; }
fi

FULLNODE_API=$(docker exec lotus lotus auth api-info --perm=admin | cut -d= -f2-)
[ -n "$FULLNODE_API" ] || { echo "ERROR: Could not get FULLNODE_API_INFO from lotus — is the lotus container running?"; exit 1; }

HEAD_EPOCH=$(docker exec lotus lotus chain head --height | tr -d '\r\n ')
START_EPOCH_OFFSET="${DIRECT_IMPORT_START_EPOCH_OFFSET:-55}"
START_EPOCH=$((HEAD_EPOCH + START_EPOCH_OFFSET))
state_set DIRECT_IMPORT_START_EPOCH "$START_EPOCH"

echo "=== Import Piece ==="
echo "  Allocation: $ALLOC_ID"
echo "  Piece CID:  $PIECE_CID"
echo "  Start epoch: $START_EPOCH (head $HEAD_EPOCH + $START_EPOCH_OFFSET)"

docker exec -e FULLNODE_API_INFO="$FULLNODE_API" boost boostd import-direct \
    --client-addr="$CLIENT_F4" \
    --allocation-id="$ALLOC_ID" \
    --start-epoch="$START_EPOCH" \
    "$PIECE_CID" "$PIECE_CAR_PATH" 2>&1 || \
    { echo "  WARN: Retrying in 30s..."; sleep 30
      HEAD_EPOCH=$(docker exec lotus lotus chain head --height | tr -d '\r\n ')
      START_EPOCH=$((HEAD_EPOCH + START_EPOCH_OFFSET))
      state_set DIRECT_IMPORT_START_EPOCH "$START_EPOCH"
      docker exec -e FULLNODE_API_INFO="$FULLNODE_API" boost boostd import-direct \
          --client-addr="$CLIENT_F4" \
          --allocation-id="$ALLOC_ID" \
          --start-epoch="$START_EPOCH" \
          "$PIECE_CID" "$PIECE_CAR_PATH" 2>&1 || { echo "ERROR: import-direct failed"; exit 1; }; }

echo "=== Piece imported ==="
