#!/bin/bash
POREP_MARKET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${SCRIPT_DIR:-$POREP_MARKET_ROOT}"
ENV_FILE="$POREP_MARKET_ROOT/.env"
POREP_DIR="$POREP_MARKET_ROOT/porep-market"
METAALLOC_DIR="$POREP_MARKET_ROOT/contract-metaallocator"
POREP_TOOLING_DIR="$POREP_MARKET_ROOT/filecoin-porep-market-tooling"

_safe_source_kvfile() {
    local file="$1"
    [ -f "$file" ] || return 0
    while IFS='=' read -r key val; do
        key="${key%%[[:space:]]}"
        val="${val##[[:space:]]}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]] || continue
        [ -n "$key" ] || continue
        export "$key=$val"
    done < "$file"
}

_sed_i() {
    local expr="$1" file="$2"
    local tmp
    tmp=$(mktemp)
    sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
}

if [ -f "$ENV_FILE" ]; then
    _safe_source_kvfile "$ENV_FILE"
fi

RPC_URL="${RPC_URL:-http://127.0.0.1:1234/rpc/v1}"
MINER_ACTOR_ID="${MINER_ACTOR_ID:-1000}"

require_env() {
    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            echo "ERROR: $var not set. Check $ENV_FILE" && exit 1
        fi
    done
}

require_devnet() {
    docker exec lotus lotus chain head &>/dev/null || { echo "ERROR: Devnet not running (make devnet/up)"; exit 1; }
}

require_porep() {
    [ -d "$POREP_DIR" ] || { echo "ERROR: porep-market not cloned. Run 00_setup.sh"; exit 1; }
}

update_env() {
    local key="$1" val="$2"
    [ -f "$ENV_FILE" ] || cp "$POREP_MARKET_ROOT/env.example" "$ENV_FILE"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        _sed_i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        echo "${key}=${val}" >> "$ENV_FILE"
    fi
}

wait_for_tx() {
    local tx_hash="${1:-}"
    if [ -z "$tx_hash" ]; then
        echo "WARN: wait_for_tx called without a tx hash; sleeping 15s for backward compatibility" >&2
        sleep 15
        return 0
    fi
    local attempts=0
    while [ $attempts -lt 60 ]; do
        local status
        status=$(extract_status "$(cast receipt --rpc-url "$RPC_URL" "$tx_hash" --json 2>&1)" 2>/dev/null) || true
        if [ "$status" = "0x1" ]; then
            return 0
        elif [ "$status" = "0x0" ]; then
            echo "ERROR: tx $tx_hash reverted"
            return 1
        fi
        attempts=$((attempts + 1))
        [ $((attempts % 6)) -ne 0 ] || echo "  [wait_for_tx] still waiting for ${tx_hash:0:12}... (${attempts} checks / $((attempts * 5))s)" >&2
        sleep 5
    done
    echo "ERROR: tx $tx_hash not mined after 5 minutes"
    return 1
}

wait_for_block() {
    local target_block="${1:-}"
    local current_block
    if [ -z "$target_block" ]; then
        echo "ERROR: target block required" >&2
        return 1
    fi
    current_block=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null)
    while [ "$current_block" -lt "$target_block" ]; do
        echo "  [wait_for_block] still waiting for ${target_block} (${current_block} / ${target_block})" >&2
        sleep 5
        current_block=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null)
    done
}

# --- State file management ---
STATE_FILE="${STATE_FILE:-$POREP_MARKET_ROOT/.state}"

state_set() {
    local key="$1" val="$2"
    if [ ! -f "$STATE_FILE" ]; then
        [ -f "$POREP_MARKET_ROOT/state.example" ] && cp "$POREP_MARKET_ROOT/state.example" "$STATE_FILE" || touch "$STATE_FILE"
    fi
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        _sed_i "s|^${key}=.*|${key}=${val}|" "$STATE_FILE"
    else
        echo "${key}=${val}" >> "$STATE_FILE"
    fi
    export "$key=$val"
}

state_get() {
    local key="$1"
    if [ -n "${!key:-}" ]; then
        echo "${!key}"
        return
    fi
    if [ -f "$STATE_FILE" ]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2-
    fi
}

state_require() {
    for var in "$@"; do
        local val
        val=$(state_get "$var")
        if [ -z "$val" ]; then
            echo "ERROR: $var not in state. Run prerequisite step first." && exit 1
        fi
        export "$var=$val"
    done
}

state_load() {
    _safe_source_kvfile "$STATE_FILE"
}

state_init() {
    STATE_FILE="${1:-$STATE_FILE}"
    export STATE_FILE
    state_load
}

# --- Cast helpers ---
json_from_output() {
    local output="$1"
    printf '%s\n' "$output" | awk 'BEGIN{capture=0} /^[[:space:]]*[{[]/ {capture=1} capture {print}'
}

extract_json_field() {
    local output="$1" filter="$2"
    local json
    json=$(json_from_output "$output")
    [ -n "$json" ] || return 1
    printf '%s\n' "$json" | jq -r "$filter // empty" 2>/dev/null
}

extract_tx_hash() {
    local output="$1"
    local tx_hash
    tx_hash=$(extract_json_field "$output" '.transactionHash' || true)
    if [ -n "$tx_hash" ] && [ "$tx_hash" != "null" ]; then
        echo "$tx_hash"
        return 0
    fi
    tx_hash=$(printf '%s\n' "$output" | rg -o '0x[0-9a-fA-F]{64}' | tail -n 1 || true)
    [ -n "$tx_hash" ] || return 1
    echo "$tx_hash"
}

extract_status() {
    local output="$1"
    local status
    status=$(extract_json_field "$output" '.status' || true)
    if [ -n "$status" ] && [ "$status" != "null" ]; then
        echo "$status"
        return 0
    fi
    status=$(printf '%s\n' "$output" | rg -o '0x[01]' | tail -n 1 || true)
    [ -n "$status" ] || return 1
    echo "$status"
}

send_tx_output() {
    local key="${SENDER_KEY:-$PRIVATE_KEY_TEST}"
    local stderr_tmp
    stderr_tmp=$(mktemp)
    local output
    output=$(cast send --gas-limit 9000000000 --rpc-url "$RPC_URL" --private-key "$key" "$@" --json 2>"$stderr_tmp") || true
    if [ -s "$stderr_tmp" ]; then
        sed 's/--private-key 0x[0-9a-fA-F]*/--private-key REDACTED/g' "$stderr_tmp" >&2
    fi
    rm -f "$stderr_tmp"
    printf '%s\n' "$output"
}

send_tx_hash() {
    local output tx_hash
    output=$(send_tx_output "$@")
    tx_hash=$(extract_tx_hash "$output" || true)
    if [ -z "$tx_hash" ]; then
        echo "ERROR: cast send failed (no tx hash in output)" >&2
        return 1
    fi
    echo "$tx_hash"
}

receipt_json() {
    local tx_hash="$1"
    local output json
    output=$(cast receipt --rpc-url "$RPC_URL" "$tx_hash" --json 2>&1)
    json=$(json_from_output "$output")
    if [ -z "$json" ]; then
        echo "ERROR: failed to parse receipt JSON for tx $tx_hash" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
    printf '%s\n' "$json"
}

rpc_eth_call_result() {
    local to="$1" data="$2"
    local payload response result
    payload=$(jq -n --arg to "$to" --arg data "$data" \
        '{jsonrpc:"2.0",method:"eth_call",params:[{to:$to,data:$data},"latest"],id:1}')
    response=$(curl -s -X POST -H 'Content-Type: application/json' \
        --data "$payload" "$RPC_URL")
    result=$(printf '%s\n' "$response" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$result" ] || [ "$result" = "null" ]; then
        echo "ERROR: failed eth_call to $to" >&2
        printf '%s\n' "$response" >&2
        return 1
    fi
    printf '%s\n' "$result"
}

decode_eth_call_json() {
    local to="$1" calldata_sig="$2" decode_sig="$3"
    shift 3
    local data raw
    data=$(cast calldata "$calldata_sig" "$@")
    raw=$(rpc_eth_call_result "$to" "$data")
    cast decode-abi "$decode_sig" "$raw" --json
}

csend() {
    local tx_hash
    tx_hash=$(send_tx_hash "$@")
    wait_for_tx "$tx_hash"
}

require_code_at() {
    local addr="$1" label="${2:-contract}"
    local code
    code=$(cast code --rpc-url "$RPC_URL" "$addr" 2>/dev/null || echo "0x")
    [ "$code" != "0x" ] || {
        echo "ERROR: no code found at $label address $addr" >&2
        exit 1
    }
}

ccall() {
    cast call --rpc-url "$RPC_URL" "$@"
}

json_tuple_field() {
    local json="$1" index="$2"
    printf '%s\n' "$json" | jq -r --argjson i "$index" '
        if (.[0] | type) == "array" then
            .[0][$i]
        elif (.[0] | type) == "string" then
            .[0] | sub("^\\("; "") | sub("\\)$"; "") | split(", ")[$i]
        else
            empty
        end
    '
}

get_deal_field() {
    local deal_id="$1" field="$2"
    local decoded tuple_index

    case "$field" in
        1|2|3|11|12|13)
            decoded=$(decode_eth_call_json \
                "$POREP_MARKET" \
                "getDeal(uint256)" \
                "getDeal(uint256)((uint256,address,uint64,uint256,uint8,address,address,uint256))" \
                "$deal_id")
            case "$field" in
                1) tuple_index=0 ;;
                2) tuple_index=1 ;;
                3) tuple_index=2 ;;
                11) tuple_index=6 ;;
                12) tuple_index=4 ;;
                13) tuple_index=7 ;;
            esac
            ;;
        4|5|6|7)
            decoded=$(decode_eth_call_json \
                "$POREP_MARKET" \
                "getDealSLIs(uint256)" \
                "getDealSLIs(uint256)((uint16,uint64,uint16,uint8))" \
                "$deal_id")
            case "$field" in
                4) tuple_index=0 ;;
                5) tuple_index=1 ;;
                6) tuple_index=2 ;;
                7) tuple_index=3 ;;
            esac
            ;;
        8|10)
            decoded=$(decode_eth_call_json \
                "$POREP_MARKET" \
                "getDealTerms(uint256)" \
                "getDealTerms(uint256)((uint256,uint64))" \
                "$deal_id")
            case "$field" in
                8) tuple_index=0 ;;
                10) tuple_index=1 ;;
            esac
            ;;
        9)
            decoded=$(decode_eth_call_json \
                "$POREP_MARKET" \
                "getDealPayment(uint256)" \
                "getDealPayment(uint256)((address,address,uint256,uint256,uint256))" \
                "$deal_id")
            tuple_index=2
            ;;
        15)
            decoded=$(decode_eth_call_json \
                "$POREP_MARKET" \
                "getDealData(uint256)" \
                "getDealData(uint256)((bytes32,string))" \
                "$deal_id")
            tuple_index=1
            ;;
        *) echo "ERROR: unsupported deal field index $field" >&2; return 1 ;;
    esac

    json_tuple_field "$decoded" "$tuple_index"
}

fp_balance() {
    local addr="$1"
    decode_eth_call_json \
        "$FILECOIN_PAY" \
        "accounts(address,address)" \
        "accounts(address,address)(uint256,uint256,uint256,uint256)" \
        "$USDC_TOKEN" "$addr" | jq -r 'if (.[0] | type) == "array" then .[0][0] else .[0] end'
}

rail_payment_rate() {
    local rail_id="$1"
    decode_eth_call_json \
        "$FILECOIN_PAY" \
        "getRail(uint256)" \
        "getRail(uint256)((address,address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,address))" \
        "$rail_id" | jq -r '.[0][5]'
}

rail_settled_up_to() {
    local rail_id="$1"
    decode_eth_call_json \
        "$FILECOIN_PAY" \
        "getRail(uint256)" \
        "getRail(uint256)((address,address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,address))" \
        "$rail_id" | jq -r '.[0][8]'
}

rail_end_epoch() {
    local rail_id="$1"
    decode_eth_call_json \
        "$FILECOIN_PAY" \
        "getRail(uint256)" \
        "getRail(uint256)((address,address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,address))" \
        "$rail_id" | jq -r '.[0][9]'
}
