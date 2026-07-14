#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST SLI_ORACLE

state_load
state_require DEAL_ID

DEAL_SLIS_JSON=$(get_v2_deal_slis_json "$DEAL_ID")
DEFAULT_RETRIEVABILITY_BPS=$(printf '%s\n' "$DEAL_SLIS_JSON" | jq -r '.[0][0]')
DEFAULT_BANDWIDTH_BYTES_PER_SECOND=$(printf '%s\n' "$DEAL_SLIS_JSON" | jq -r '.[0][1]')
DEFAULT_LATENCY_MS=$(printf '%s\n' "$DEAL_SLIS_JSON" | jq -r '.[0][2]')
DEFAULT_INDEXING_PCT=$(printf '%s\n' "$DEAL_SLIS_JSON" | jq -r '.[0][3]')

RETRIEVABILITY_BPS="${V2_SLI_RETRIEVABILITY_BPS:-$DEFAULT_RETRIEVABILITY_BPS}"
BANDWIDTH_BYTES_PER_SECOND="${V2_SLI_BANDWIDTH_BYTES_PER_SECOND:-$DEFAULT_BANDWIDTH_BYTES_PER_SECOND}"
LATENCY_MS="${V2_SLI_LATENCY_MS:-$DEFAULT_LATENCY_MS}"
INDEXING_PCT="${V2_SLI_INDEXING_PCT:-$DEFAULT_INDEXING_PCT}"

echo "=== Set V2 SLI attestation ==="
echo "  Deal: $DEAL_ID"
echo "  SLIOracle: $SLI_ORACLE"
echo "  Retrievability bps: $RETRIEVABILITY_BPS"
echo "  Bandwidth bytes/s: $BANDWIDTH_BYTES_PER_SECOND"
echo "  Latency ms: $LATENCY_MS"
echo "  Indexing pct: $INDEXING_PCT"

TX_HASH=$(send_tx_hash \
    "$SLI_ORACLE" \
    "setSLI(uint256,(uint16,uint64,uint16,uint8))" \
    "$DEAL_ID" \
    "($RETRIEVABILITY_BPS,$BANDWIDTH_BYTES_PER_SECOND,$LATENCY_MS,$INDEXING_PCT)")
wait_for_tx "$TX_HASH"

ATTESTATION_JSON=$(decode_eth_call_json \
    "$SLI_ORACLE" \
    "getAttestation(uint256)" \
    "getAttestation(uint256)((uint256,(uint16,uint64,uint16,uint8)))" \
    "$DEAL_ID")

LAST_UPDATE=$(printf '%s\n' "$ATTESTATION_JSON" | jq -r '.[0][0]')
ACTUAL_RETRIEVABILITY_BPS=$(printf '%s\n' "$ATTESTATION_JSON" | jq -r '.[0][1][0]')
ACTUAL_BANDWIDTH_BYTES_PER_SECOND=$(printf '%s\n' "$ATTESTATION_JSON" | jq -r '.[0][1][1]')
ACTUAL_LATENCY_MS=$(printf '%s\n' "$ATTESTATION_JSON" | jq -r '.[0][1][2]')
ACTUAL_INDEXING_PCT=$(printf '%s\n' "$ATTESTATION_JSON" | jq -r '.[0][1][3]')

[ "$LAST_UPDATE" -gt 0 ] || { echo "ERROR: SLI attestation lastUpdate expected > 0, got $LAST_UPDATE"; exit 1; }
[ "$ACTUAL_RETRIEVABILITY_BPS" = "$RETRIEVABILITY_BPS" ] || { echo "ERROR: retrievability expected $RETRIEVABILITY_BPS, got $ACTUAL_RETRIEVABILITY_BPS"; exit 1; }
[ "$ACTUAL_BANDWIDTH_BYTES_PER_SECOND" = "$BANDWIDTH_BYTES_PER_SECOND" ] || { echo "ERROR: bandwidth expected $BANDWIDTH_BYTES_PER_SECOND, got $ACTUAL_BANDWIDTH_BYTES_PER_SECOND"; exit 1; }
[ "$ACTUAL_LATENCY_MS" = "$LATENCY_MS" ] || { echo "ERROR: latency expected $LATENCY_MS, got $ACTUAL_LATENCY_MS"; exit 1; }
[ "$ACTUAL_INDEXING_PCT" = "$INDEXING_PCT" ] || { echo "ERROR: indexing expected $INDEXING_PCT, got $ACTUAL_INDEXING_PCT"; exit 1; }

state_set SLI_ATTESTATION_TX "$TX_HASH"
state_set SLI_LAST_UPDATE "$LAST_UPDATE"
state_set SLI_RETRIEVABILITY_BPS "$ACTUAL_RETRIEVABILITY_BPS"
state_set SLI_BANDWIDTH_BYTES_PER_SECOND "$ACTUAL_BANDWIDTH_BYTES_PER_SECOND"
state_set SLI_LATENCY_MS "$ACTUAL_LATENCY_MS"
state_set SLI_INDEXING_PCT "$ACTUAL_INDEXING_PCT"

echo "  TX: $TX_HASH"
echo "  Last update epoch: $LAST_UPDATE"
echo "=== V2 SLI attestation set ==="
