#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common.sh"

assert_equals() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" != "$actual" ]; then
        echo "ERROR: $label expected $expected, got $actual" >&2
        exit 1
    fi
}
