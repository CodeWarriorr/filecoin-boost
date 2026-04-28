#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../setup"
STEPS="$SCRIPT_DIR/../steps"
source "$SCRIPT_DIR/_common.sh"
source "$SCRIPT_DIR/../tooling/_common.sh"

require_devnet
require_tooling

STATE_FILE="/tmp/porep-tooling-happy-path-$$.state"
MANIFEST_DIR="/tmp/porep-tooling-manifest-$$"
export STATE_FILE

cleanup() {
    rm -rf "$MANIFEST_DIR"
}
trap cleanup EXIT

echo "State: $STATE_FILE"
echo "============================================================"
echo "  TOOLING HAPPY PATH VERIFIED"
echo "============================================================"

bash "$SETUP/06_prepare_operator.sh"
GENERATE_PIECE=1 bash "$SETUP/07_generate_piece.sh"

state_load
state_require PIECE_CID PIECE_SIZE PIECE_CAR_PATH

mkdir -p "$MANIFEST_DIR"
MANIFEST_FILE="$MANIFEST_DIR/manifest.json"
DAG_PIECE_CID="${TOOLING_DAG_PIECE_CID:-baga6ea4seaqkw2fqpbilvzkewttsb72z7xd544e2rnni5a6ww6vtvqx2qpuemgy}"
DAG_PIECE_SIZE="${TOOLING_DAG_PIECE_SIZE:-1048576}"

jq -n \
    --arg dag_cid "$DAG_PIECE_CID" \
    --argjson dag_size "$DAG_PIECE_SIZE" \
    --arg data_cid "$PIECE_CID" \
    --argjson data_size "$PIECE_SIZE" '
[
  {
    pieces: [
      {
        pieceCid: $dag_cid,
        pieceType: "dag",
        pieceSize: $dag_size,
        preparationId: 1,
        attachmentId: 1,
        storagePath: "/devnet/dag.car"
      },
      {
        pieceCid: $data_cid,
        pieceType: "data",
        pieceSize: $data_size,
        preparationId: 1,
        attachmentId: 1,
        storagePath: "/devnet/data.car"
      }
    ]
  }
]
' > "$MANIFEST_FILE"

if [ -n "${TOOLING_MANIFEST_URL:-}" ]; then
    MANIFEST_URL="$TOOLING_MANIFEST_URL"
else
    UPLOAD_RESPONSE=$(curl -fsS -F "file=@${MANIFEST_FILE};filename=manifest.json" https://tmpfiles.org/api/v1/upload)
    MANIFEST_URL=$(printf '%s\n' "$UPLOAD_RESPONSE" | jq -r '.data.url // empty' | sed 's|://tmpfiles.org/|://tmpfiles.org/dl/|')
fi

[ -n "$MANIFEST_URL" ] || { echo "ERROR: failed to prepare public manifest URL" >&2; exit 1; }
curl -fsS "$MANIFEST_URL" | jq -e 'type == "array"' >/dev/null
echo "Manifest: $MANIFEST_URL"

tooling_cli_yes client propose-deal-from-manifest \
    --retrievability-bps 0 \
    --bandwidth-mbps 0 \
    --price-per-sector-per-month 86400000000 \
    --duration-months 12 \
    --latency-ms 0 \
    --indexing-pct 0 \
    "$MANIFEST_URL"

DEAL_ID=$(tooling_latest_deal_id_for_manifest "$MANIFEST_URL")
[ -n "$DEAL_ID" ] || { echo "ERROR: could not resolve tooling-created deal id" >&2; exit 1; }
state_set DEAL_ID "$DEAL_ID"
echo "Deal ID: $DEAL_ID"

SP_PRIVATE_KEY="$PRIVATE_KEY_TEST" tooling_cli_yes sp accept-deal "$DEAL_ID"
tooling_cli_yes client init-accepted-deals "$DEAL_ID"

state_load
VALIDATOR=$(get_deal_field "$DEAL_ID" 11)
RAIL_ID=$(get_deal_field "$DEAL_ID" 13)
[ -n "$VALIDATOR" ] && [ "$VALIDATOR" != "0x0000000000000000000000000000000000000000" ] || {
    echo "ERROR: validator not set by tooling" >&2
    exit 1
}
[ -n "$RAIL_ID" ] && [ "$RAIL_ID" != "0" ] || {
    echo "ERROR: rail id not set by tooling" >&2
    exit 1
}
state_set VALIDATOR "$VALIDATOR"
state_set RAIL_ID "$RAIL_ID"

tooling_cli_yes client make-allocation --exclude-dag "$DEAL_ID"

DEAL_STATE=$(get_deal_field "$DEAL_ID" 12)
assert_eq "$DEAL_STATE" "2" "deal should be Completed after tooling make-allocation"

ALLOC_ID=$(ccall "$CLIENT_CONTRACT" \
    "getClientAllocationIdsPerDeal(uint256)(uint64[])" "$DEAL_ID" 2>/dev/null | \
    tr -d '[]' | tr ',' '\n' | tail -1 | tr -d ' ')
[ -n "$ALLOC_ID" ] && [ "$ALLOC_ID" -gt 0 ] || { echo "ERROR: Could not get allocation ID"; exit 1; }
state_set ALLOC_ID "$ALLOC_ID"

bash "$SETUP/08_ensure_boost.sh"
bash "$STEPS/14_import_piece.sh"

echo "============================================================"
echo "  WAITING FOR CLAIM"
echo "============================================================"
bash "$STEPS/16_wait_for_claim.sh"

echo "RESULT: Tooling happy path reached claim successfully."
echo "============================================================"
