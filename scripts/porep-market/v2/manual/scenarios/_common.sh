#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../_common.sh"

assert_equals() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" != "$actual" ]; then
        echo "ERROR: $label expected $expected, got $actual" >&2
        exit 1
    fi
}

default_v2_deposit_amount() {
    if [ -n "${V2_DEPOSIT_AMOUNT:-}" ]; then
        echo "$V2_DEPOSIT_AMOUNT"
        return
    fi

    local price margin base_units
    price="${V2_PRICE_PER_32GIB_MONTH:-86400000000}"
    margin=$(( (price * 110 + 99) / 100 ))
    base_units=$(( (margin + 999999) / 1000000 ))
    echo "$base_units"
}
