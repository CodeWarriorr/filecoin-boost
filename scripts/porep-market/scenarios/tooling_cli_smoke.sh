#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
source "$SCRIPT_DIR/../tooling/_common.sh"

require_devnet
require_tooling
require_env POREP_MARKET CLIENT_CONTRACT SP_REGISTRY VALIDATOR_FACTORY FILECOIN_PAY USDC_TOKEN

echo "============================================================"
echo "  TOOLING CLI SMOKE"
echo "============================================================"
echo "Tooling: $POREP_TOOLING_DIR"
echo "Python:  $POREP_TOOLING_PYTHON"

tooling_cli --help >/dev/null
tooling_cli info >/dev/null
tooling_cli admin get-deals --help >/dev/null
tooling_cli client get-deals --help >/dev/null
tooling_cli client make-allocation --help >/dev/null
tooling_cli sp get-deals --help >/dev/null

ADMIN_DEALS_JSON=$(mktemp)
CLIENT_DEALS_JSON=$(mktemp)
SP_DEALS_JSON=$(mktemp)
trap 'rm -f "$ADMIN_DEALS_JSON" "$CLIENT_DEALS_JSON" "$SP_DEALS_JSON"' EXIT

tooling_cli admin get-deals > "$ADMIN_DEALS_JSON"
tooling_cli client get-deals > "$CLIENT_DEALS_JSON"
tooling_cli sp get-deals > "$SP_DEALS_JSON"

jq -e 'type == "array"' "$ADMIN_DEALS_JSON" >/dev/null
jq -e 'type == "array"' "$CLIENT_DEALS_JSON" >/dev/null
jq -e 'type == "array"' "$SP_DEALS_JSON" >/dev/null

echo "RESULT: Tooling CLI smoke passed."
echo "============================================================"
