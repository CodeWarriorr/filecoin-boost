#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

REPO="${POREP_MARKET_REPO:-https://github.com/fidlabs/porep-market.git}"
BRANCH="${POREP_MARKET_BRANCH:-$POREP_MARKET_V1_BRANCH}"

command -v forge &>/dev/null || { echo "ERROR: foundry not installed (https://getfoundry.sh)"; exit 1; }

if [ -d "$POREP_DIR" ]; then
    echo "porep-market already cloned, pulling $BRANCH..."
    cd "$POREP_DIR" && git fetch origin && git checkout "$BRANCH" && git pull origin "$BRANCH"
else
    echo "Cloning porep-market ($BRANCH)..."
    git clone --branch "$BRANCH" "$REPO" "$POREP_DIR"
fi

cd "$POREP_DIR"
forge install
forge build

# filecoin-pay (needed for deploy)
FILPAY_DIR="$POREP_MARKET_ROOT/filecoin-pay"
FILPAY_REPO="${FILECOIN_PAY_REPO:-https://github.com/FilOzone/filecoin-pay.git}"

if [ -d "$FILPAY_DIR" ]; then
    cd "$FILPAY_DIR" && git pull origin main 2>/dev/null || true
else
    git clone "$FILPAY_REPO" "$FILPAY_DIR"
fi

cd "$FILPAY_DIR"
forge install 2>/dev/null || true
forge build

# contract-metaallocator (needed for datacap allocation)
METAALLOC_REPO="${METAALLOCATOR_REPO:-https://github.com/fidlabs/contract-metaallocator.git}"

if [ -d "$METAALLOC_DIR" ]; then
    cd "$METAALLOC_DIR" && git pull origin main 2>/dev/null || true
else
    git clone "$METAALLOC_REPO" "$METAALLOC_DIR"
fi

cd "$METAALLOC_DIR"
forge install 2>/dev/null || true
forge build

# filecoin-porep-market-tooling (Python CLI used by integration scenarios)
POREP_TOOLING_REPO="${POREP_TOOLING_REPO:-https://github.com/pingwindyktator/filecoin-porep-market-tooling.git}"
POREP_TOOLING_BRANCH="${POREP_TOOLING_BRANCH:-master}"

if [ -d "$POREP_TOOLING_DIR/.git" ]; then
    if [ -n "$(git -C "$POREP_TOOLING_DIR" status --porcelain)" ]; then
        echo "ERROR: filecoin-porep-market-tooling checkout has local changes: $POREP_TOOLING_DIR" >&2
        echo "Commit, stash, or remove them before updating." >&2
        exit 1
    fi
    echo "filecoin-porep-market-tooling already cloned, pulling $POREP_TOOLING_BRANCH..."
    git -C "$POREP_TOOLING_DIR" fetch origin
    git -C "$POREP_TOOLING_DIR" checkout "$POREP_TOOLING_BRANCH"
    git -C "$POREP_TOOLING_DIR" pull --ff-only origin "$POREP_TOOLING_BRANCH"
else
    echo "Cloning filecoin-porep-market-tooling ($POREP_TOOLING_BRANCH)..."
    git clone --branch "$POREP_TOOLING_BRANCH" "$POREP_TOOLING_REPO" "$POREP_TOOLING_DIR"
fi

python3 -m venv "$POREP_TOOLING_DIR/.venv"
"$POREP_TOOLING_DIR/.venv/bin/pip" install -r "$POREP_TOOLING_DIR/requirements.txt"

if command -v npm &>/dev/null && [ -f "$POREP_MARKET_ROOT/v1/steps/package.json" ]; then
    npm --prefix "$POREP_MARKET_ROOT/v1/steps" ci
fi

echo "Done."
