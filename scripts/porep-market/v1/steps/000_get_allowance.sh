#!/bin/bash
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

require_devnet
require_env META_ALLOCATOR
require_env CLIENT_CONTRACT

echo "Checking allowance..."
echo "Meta Allocator:   $META_ALLOCATOR"
echo "Allocator:        $CLIENT_CONTRACT"
echo ""

ALLOWANCE=$(cast call \
  "$META_ALLOCATOR" \
  "allowance(address)(uint256)" \
  "$CLIENT_CONTRACT" \
  --rpc-url "$RPC_URL"
)

echo "Allowance:"
echo "$ALLOWANCE"