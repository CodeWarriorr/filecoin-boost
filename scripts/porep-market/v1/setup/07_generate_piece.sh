#!/bin/bash
# Params:
#   GENERATE_PIECE  - set to 1 to generate a new random CAR file instead of using the sample
# State out: PIECE_CID, PIECE_SIZE, PIECE_CID_HEX, PIECE_CAR_PATH
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet

state_load

echo "=== Generate Piece ==="

if [ "${GENERATE_PIECE:-}" = "1" ]; then
    PIECE_DIR="/tmp/testpiece-$$"
    PIECE_CAR_PATH="$PIECE_DIR/piece.car"
    docker exec boost bash -c "
        mkdir -p '$PIECE_DIR'
        dd if=/dev/urandom bs=1 count=1500 of='$PIECE_DIR/rand.bin' 2>/dev/null
        car create --no-wrap -f '$PIECE_CAR_PATH' '$PIECE_DIR/rand.bin' 2>/dev/null
    " 2>/dev/null
    echo "  (generated new random CAR)"
else
    PIECE_CAR_PATH="/app/sample/bafykbzacec432ygday37lj2tvl3e7wl7ij46dko7cbmlndeghx6lhjkluqzhg.car"
    echo "  (using sample CAR; set GENERATE_PIECE=1 to generate a new one)"
fi

COMMP_OUTPUT=$(docker exec boost boostx commp "$PIECE_CAR_PATH" 2>/dev/null)
PIECE_CID=$(echo "$COMMP_OUTPUT" | grep "^CommP CID:" | awk '{print $3}')
PIECE_SIZE=$(echo "$COMMP_OUTPUT" | grep "^Piece size:" | awk '{print $3}')

[ -n "$PIECE_CID" ] && [ -n "$PIECE_SIZE" ] || {
    echo "ERROR: Failed to compute CommP. Output:"
    echo "$COMMP_OUTPUT"
    exit 1
}

if [[ "$PIECE_CID" == Qm* ]]; then
    echo "ERROR: CIDv0 input ($PIECE_CID) is not supported; boostx commp should return CIDv1"
    exit 1
fi

PIECE_CID_HEX=$(python3 -c "
import base64, sys
cid = sys.argv[1]
encoded = cid[1:].upper()
pad = '=' * ((-len(encoded)) % 8)
raw = base64.b32decode(encoded + pad)
print(raw.hex())
" "$PIECE_CID")

[ -n "$PIECE_CID_HEX" ] || { echo "ERROR: Failed to convert piece CID to hex"; exit 1; }

state_set PIECE_CID "$PIECE_CID"
state_set PIECE_SIZE "$PIECE_SIZE"
state_set PIECE_CID_HEX "$PIECE_CID_HEX"
state_set PIECE_CAR_PATH "$PIECE_CAR_PATH"

echo "  CID:  $PIECE_CID"
echo "  Size: $PIECE_SIZE"
echo "=== Piece generated ==="
