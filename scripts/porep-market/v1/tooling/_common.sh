#!/bin/bash

TOOLING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TOOLING_SCRIPT_DIR/../_common.sh"

POREP_TOOLING_PYTHON="$POREP_TOOLING_DIR/.venv/bin/python"
POREP_TOOLING_CLI="$POREP_TOOLING_DIR/porep_tooling_cli.py"

require_tooling() {
    [ -d "$POREP_TOOLING_DIR/.git" ] || {
        echo "ERROR: filecoin-porep-market-tooling not cloned. Run setup/00_setup.sh" >&2
        exit 1
    }
    [ -x "$POREP_TOOLING_PYTHON" ] || {
        echo "ERROR: Python tooling venv missing. Run setup/00_setup.sh" >&2
        exit 1
    }
    [ -f "$POREP_TOOLING_CLI" ] || {
        echo "ERROR: Python tooling CLI missing at $POREP_TOOLING_CLI" >&2
        exit 1
    }
}

tooling_export_env() {
    require_env RPC_URL PRIVATE_KEY_TEST PRIVATE_KEY_SP POREP_MARKET CLIENT_CONTRACT \
                SP_REGISTRY VALIDATOR_FACTORY FILECOIN_PAY USDC_TOKEN

    export RPC_URL
    export DEBUG="${DEBUG:-true}"
    export DRY_RUN="${DRY_RUN:-false}"
    export SP_REGISTRY_DATABASE_URL="${SP_REGISTRY_DATABASE_URL:-}"

    export ADMIN_PRIVATE_KEY="${ADMIN_PRIVATE_KEY:-$PRIVATE_KEY_TEST}"
    export CLIENT_PRIVATE_KEY="${CLIENT_PRIVATE_KEY:-$PRIVATE_KEY_TEST}"
    export SP_PRIVATE_KEY="${SP_PRIVATE_KEY:-$PRIVATE_KEY_SP}"

    export POREP_MARKET
    export CLIENT_CONTRACT
    export SP_REGISTRY
    export VALIDATOR_FACTORY
    export FILECOIN_PAY
    export USDC_TOKEN
}

tooling_cli() {
    require_tooling
    tooling_export_env
    (
        cd "$POREP_TOOLING_DIR"
        "$POREP_TOOLING_PYTHON" "$POREP_TOOLING_CLI" "$@"
    )
}

tooling_cli_yes() {
    local status
    set +o pipefail
    yes y | tooling_cli "$@"
    status=${PIPESTATUS[1]}
    set -o pipefail
    return "$status"
}

tooling_latest_deal_id_for_manifest() {
    local manifest_url="$1"
    tooling_cli client get-deals | jq -r --arg manifest "$manifest_url" '
        [
            .[]
            | select(.manifest_location == $manifest)
            | .deal_id
        ]
        | max // empty
    '
}
