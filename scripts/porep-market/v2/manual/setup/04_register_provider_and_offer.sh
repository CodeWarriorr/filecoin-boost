#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../setup/_common.sh"
require_devnet
require_env PRIVATE_KEY_TEST PRIVATE_KEY_SP SP_REGISTRY

DEPLOYER=$(cast wallet address "$PRIVATE_KEY_TEST")
PROVIDER_PAYEE="${V2_PROVIDER_PAYEE:-$(cast wallet address "$PRIVATE_KEY_SP")}"
[ "$(lower_hex "$PROVIDER_PAYEE")" != "$(lower_hex "$DEPLOYER")" ] || {
    echo "ERROR: V2 provider payee must differ from client/deployer for payout assertions" >&2
    exit 1
}

echo "=== Register V2 provider in SPRegistry ==="
echo "Current PoRep Market V2 uses provider registration plus offer-based matching."

MINER_ID="${MINER_ACTOR_ID:-1000}"
RETRIEVABILITY_BPS="${V2_RETRIEVABILITY_BPS:-10000}"
BANDWIDTH_BYTES_PER_SECOND="${V2_BANDWIDTH_BYTES_PER_SECOND:-1048576}"
LATENCY_MS="${V2_LATENCY_MS:-100}"
INDEXING_PCT="${V2_INDEXING_PCT:-100}"
AVAILABLE_BYTES="${V2_AVAILABLE_BYTES:-1073741824}"
PRICE_PER_32GIB_MONTH="${V2_PRICE_PER_32GIB_MONTH:-86400000000}"
MIN_SIZE_BYTES="${V2_MIN_SIZE_BYTES:-1}"
MAX_SIZE_BYTES="${V2_MAX_SIZE_BYTES:-0}"
MIN_DURATION_EPOCHS="${V2_MIN_DURATION_EPOCHS:-518400}"
MAX_DURATION_EPOCHS="${V2_MAX_DURATION_EPOCHS:-3680640}"
PAYMENT_TOKEN="${V2_PAYMENT_TOKEN:-${USDC_TOKEN:-}}"
MIN_PRICE_PER_32GIB_MONTH="${V2_MIN_PRICE_PER_32GIB_MONTH:-1}"

[ -n "$PAYMENT_TOKEN" ] || {
    echo "ERROR: V2 payment token required. Set V2_PAYMENT_TOKEN or USDC_TOKEN in $ENV_FILE" >&2
    exit 1
}

if cast call --rpc-url "$RPC_URL" "$SP_REGISTRY" "isProviderRegistered(uint64)(bool)" "$MINER_ID" 2>/dev/null | grep -q true; then
    echo "Provider $MINER_ID already registered, refreshing V2 smoke-test capacity and payee"
    csend "$SP_REGISTRY" "updateAvailableSpace(uint64,uint256)" "$MINER_ID" "$AVAILABLE_BYTES"
    csend "$SP_REGISTRY" "setPayee(uint64,address)" "$MINER_ID" "$PROVIDER_PAYEE"
else
    csend \
        "$SP_REGISTRY" \
        "registerProviderFor(uint64,address,uint256,address)" \
        "$MINER_ID" \
        "$DEPLOYER" \
        "$AVAILABLE_BYTES" \
        "$PROVIDER_PAYEE"
fi

registered=$(cast call --rpc-url "$RPC_URL" "$SP_REGISTRY" "isProviderRegistered(uint64)(bool)" "$MINER_ID")
[ "$registered" = "true" ] || { echo "ERROR: provider $MINER_ID was not registered"; exit 1; }

csend "$SP_REGISTRY" "setPaymentToken(address,bool,uint256)" "$PAYMENT_TOKEN" true "$MIN_PRICE_PER_32GIB_MONTH"

EXISTING_OFFER_ID=$(cast call --rpc-url "$RPC_URL" "$SP_REGISTRY" "getOffersByProvider(uint64)(uint256[])" "$MINER_ID" \
    | rg -o '[0-9]+' | head -n 1 || true)

if [ -n "$EXISTING_OFFER_ID" ] && [ "$EXISTING_OFFER_ID" != "0" ]; then
    OFFER_ID="$EXISTING_OFFER_ID"
    echo "Provider $MINER_ID already has offer $OFFER_ID, refreshing payment row"
    csend "$SP_REGISTRY" "setOfferPayment(uint256,address,bool,uint256)" \
        "$OFFER_ID" "$PAYMENT_TOKEN" true "$PRICE_PER_32GIB_MONTH"
else
    TX_HASH=$(send_tx_hash \
        "$SP_REGISTRY" \
        "createOffer(uint64,(uint256,uint256,uint64,uint64),(uint16,uint64,uint16,uint8),(address,bool,uint256)[])" \
        "$MINER_ID" \
        "($MIN_SIZE_BYTES,$MAX_SIZE_BYTES,$MIN_DURATION_EPOCHS,$MAX_DURATION_EPOCHS)" \
        "($RETRIEVABILITY_BPS,$BANDWIDTH_BYTES_PER_SECOND,$LATENCY_MS,$INDEXING_PCT)" \
        "[($PAYMENT_TOKEN,true,$PRICE_PER_32GIB_MONTH)]")
    wait_for_tx "$TX_HASH"
    RECEIPT=$(receipt_json "$TX_HASH")
    EVENT_SIG=$(cast keccak "OfferCreated(uint256,uint64)")
    OFFER_ID=$(echo "$RECEIPT" | jq -r --arg sig "$EVENT_SIG" '
        .logs[]
        | select(.topics[0]==$sig)
        | .topics[1]
    ' | cast to-dec)
    [ -n "$OFFER_ID" ] && [ "$OFFER_ID" != "0" ] || { echo "ERROR: OfferCreated event not found"; exit 1; }
fi

OFFER_VIEW=$(decode_eth_call_json \
    "$SP_REGISTRY" \
    "getOfferView(uint256,address)" \
    "getOfferView(uint256,address)((uint256,uint64,bool,(uint256,uint256,uint64,uint64),(uint16,uint64,uint16,uint8),address,bool,uint256))" \
    "$OFFER_ID" "$PAYMENT_TOKEN")
OFFER_PROVIDER=$(printf '%s\n' "$OFFER_VIEW" | jq -r '.[0][1]')
OFFER_ACTIVE=$(printf '%s\n' "$OFFER_VIEW" | jq -r '.[0][2]')
OFFER_PAYMENT_ACTIVE=$(printf '%s\n' "$OFFER_VIEW" | jq -r '.[0][6]')
OFFER_PRICE=$(printf '%s\n' "$OFFER_VIEW" | jq -r '.[0][7]')

[ "$OFFER_PROVIDER" = "$MINER_ID" ] || { echo "ERROR: offer provider expected $MINER_ID, got $OFFER_PROVIDER"; exit 1; }
[ "$OFFER_ACTIVE" = "true" ] || { echo "ERROR: offer $OFFER_ID is not active"; exit 1; }
[ "$OFFER_PAYMENT_ACTIVE" = "true" ] || { echo "ERROR: offer $OFFER_ID payment row is not active"; exit 1; }
[ "$OFFER_PRICE" = "$PRICE_PER_32GIB_MONTH" ] || { echo "ERROR: offer price expected $PRICE_PER_32GIB_MONTH, got $OFFER_PRICE"; exit 1; }

state_set PROVIDER "$MINER_ID"
state_set PROVIDER_PAYEE "$PROVIDER_PAYEE"
state_set OFFER_ID "$OFFER_ID"
echo "Provider $MINER_ID registered with offer $OFFER_ID for token $PAYMENT_TOKEN at price $PRICE_PER_32GIB_MONTH and payee $PROVIDER_PAYEE."
