#!/bin/bash
export POREP_MARKET_VERSION="${POREP_MARKET_VERSION:-v2}"
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/shared/_common.sh"
