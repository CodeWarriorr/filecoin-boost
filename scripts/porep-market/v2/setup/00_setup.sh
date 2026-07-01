#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

REPO="${POREP_MARKET_REPO:-https://github.com/fidlabs/porep-market.git}"
BRANCH="${POREP_MARKET_BRANCH:-$POREP_MARKET_V2_BRANCH}"

command -v forge &>/dev/null || { echo "ERROR: foundry not installed (https://getfoundry.sh)"; exit 1; }

if [ -d "$POREP_DIR/.git" ]; then
    if [ -n "$(git -C "$POREP_DIR" status --porcelain)" ]; then
        echo "ERROR: porep-market checkout has local changes: $POREP_DIR" >&2
        echo "Commit, stash, or use POREP_MARKET_DIR for a separate checkout." >&2
        exit 1
    fi
    echo "porep-market already cloned, pulling $BRANCH..."
    git -C "$POREP_DIR" fetch origin
    git -C "$POREP_DIR" checkout "$BRANCH"
    git -C "$POREP_DIR" pull --ff-only origin "$BRANCH"
elif [ -d "$POREP_DIR" ]; then
    echo "Using local porep-market directory: $POREP_DIR"
else
    echo "Cloning porep-market ($BRANCH)..."
    git clone --branch "$BRANCH" "$REPO" "$POREP_DIR"
fi

cd "$POREP_DIR"
forge install
forge build

FILPAY_DIR="$POREP_MARKET_ROOT/filecoin-pay"
FILPAY_REPO="${FILECOIN_PAY_REPO:-https://github.com/FilOzone/filecoin-pay.git}"

if [ -d "$FILPAY_DIR" ]; then
    git -C "$FILPAY_DIR" pull --ff-only origin main 2>/dev/null || true
else
    git clone "$FILPAY_REPO" "$FILPAY_DIR"
fi

cd "$FILPAY_DIR"
forge install 2>/dev/null || true
forge build

METAALLOC_REPO="${METAALLOCATOR_REPO:-https://github.com/fidlabs/contract-metaallocator.git}"

if [ -d "$METAALLOC_DIR" ]; then
    git -C "$METAALLOC_DIR" pull --ff-only origin main 2>/dev/null || true
else
    git clone "$METAALLOC_REPO" "$METAALLOC_DIR"
fi

cd "$METAALLOC_DIR"
forge install 2>/dev/null || true
forge build

if command -v npm &>/dev/null && [ -f "$POREP_MARKET_ROOT/v2/steps/package.json" ]; then
    npm --prefix "$POREP_MARKET_ROOT/v2/steps" ci
fi

echo "Done."
