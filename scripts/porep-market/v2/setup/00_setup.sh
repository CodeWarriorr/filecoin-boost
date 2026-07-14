#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

REPO="${POREP_MARKET_REPO:-https://github.com/fidlabs/porep-market.git}"
REF="$(resolve_porep_market_ref v2)"

command -v forge &>/dev/null || { echo "ERROR: foundry not installed (https://getfoundry.sh)"; exit 1; }

if [ -n "$POREP_MARKET_DIR" ]; then
    echo "Using local porep-market directory: $POREP_DIR"
    require_pinned_repo "PoRep Market V2" "$POREP_DIR" "$REF"
else
    checkout_pinned_repo "PoRep Market V2" "$REPO" "$POREP_DIR" "$REF"
fi

cd "$POREP_DIR"
forge install
forge build

FILPAY_DIR="$POREP_MARKET_ROOT/filecoin-pay"
FILPAY_REPO="${FILECOIN_PAY_REPO:-https://github.com/FilOzone/filecoin-pay.git}"

checkout_pinned_repo "FilecoinPay" "$FILPAY_REPO" "$FILPAY_DIR" "$FILECOIN_PAY_REF"

cd "$FILPAY_DIR"
forge install 2>/dev/null || true
forge build

METAALLOC_REPO="${METAALLOCATOR_REPO:-https://github.com/fidlabs/contract-metaallocator.git}"

checkout_pinned_repo "MetaAllocator" "$METAALLOC_REPO" "$METAALLOC_DIR" "$METAALLOCATOR_REF"

cd "$METAALLOC_DIR"
forge install 2>/dev/null || true
forge build

if command -v npm &>/dev/null && [ -f "$POREP_MARKET_ROOT/v2/manual/steps/package.json" ]; then
    npm --prefix "$POREP_MARKET_ROOT/v2/manual/steps" ci
fi

echo "Done."
