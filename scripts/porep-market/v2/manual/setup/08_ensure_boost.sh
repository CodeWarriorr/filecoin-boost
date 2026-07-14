#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POREP_MARKET_VERSION=v2 bash "$SCRIPT_DIR/../../../v1/setup/08_ensure_boost.sh"
