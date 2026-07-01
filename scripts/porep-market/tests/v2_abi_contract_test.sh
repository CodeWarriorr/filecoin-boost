#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POREP_SRC="${POREP_MARKET_SOURCE_DIR:-$(cd "$ROOT/../../.." && pwd)/2_porep_market}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file() {
    local path="$1"
    [ -f "$path" ] || fail "missing file: $path"
}

assert_grep() {
    local pattern="$1" path="$2"
    rg -q "$pattern" "$path" || fail "missing pattern '$pattern' in $path"
}

assert_not_grep() {
    local pattern="$1" path="$2"
    if rg -q "$pattern" "$path"; then
        fail "unexpected pattern '$pattern' in $path"
    fi
}

assert_file "$POREP_SRC/src/PoRepMarket.sol"
assert_file "$POREP_SRC/src/SPRegistry.sol"
assert_file "$POREP_SRC/src/DataCapEvidenceAdapter.sol"
assert_file "$POREP_SRC/src/types/SharedTypes.sol"
assert_file "$POREP_SRC/src/types/PoRepTypes.sol"
assert_file "$POREP_SRC/src/types/DealState.sol"
assert_file "$POREP_SRC/script/Deploy.s.sol"

assert_grep 'struct DealRequest' "$POREP_SRC/src/types/SharedTypes.sol"
assert_grep 'bytes32 manifestHash' "$POREP_SRC/src/types/SharedTypes.sol"
assert_grep 'uint256 requestedSizeBytes' "$POREP_SRC/src/types/SharedTypes.sol"
assert_grep 'uint256 maxPricePer32GiBPerMonth' "$POREP_SRC/src/types/SharedTypes.sol"
assert_grep 'address paymentToken' "$POREP_SRC/src/types/SharedTypes.sol"
assert_grep 'struct SLIThresholds' "$POREP_SRC/src/types/SharedTypes.sol"
assert_grep 'uint64 bandwidthBytesPerSecond' "$POREP_SRC/src/types/SharedTypes.sol"

assert_grep 'uint8 internal constant ACCEPTED = 20' "$POREP_SRC/src/types/DealState.sol"
assert_grep 'function proposeDeal\(SharedTypes.DealRequest calldata request\)' "$POREP_SRC/src/PoRepMarket.sol"
assert_grep 'function getDeal\(uint256 dealId\)' "$POREP_SRC/src/PoRepMarket.sol"
assert_grep 'function getDealData\(uint256 dealId\)' "$POREP_SRC/src/PoRepMarket.sol"
assert_grep 'function getDealTerms\(uint256 dealId\)' "$POREP_SRC/src/PoRepMarket.sol"
assert_grep 'function getDealCapacity\(uint256 dealId\)' "$POREP_SRC/src/PoRepMarket.sol"
assert_grep 'function getDealPayment\(uint256 dealId\)' "$POREP_SRC/src/PoRepMarket.sol"
assert_grep 'function getDealSLIs\(uint256 dealId\)' "$POREP_SRC/src/PoRepMarket.sol"
assert_grep 'function updateValidator\(uint256 dealId\)' "$POREP_SRC/src/PoRepMarket.sol"
assert_grep 'function updateRailId\(uint256 dealId, uint256 railId\)' "$POREP_SRC/src/PoRepMarket.sol"
assert_grep 'function registerProviderFor' "$POREP_SRC/src/SPRegistry.sol"
assert_grep 'SharedTypes.SLIThresholds calldata capabilities' "$POREP_SRC/src/SPRegistry.sol"
assert_grep 'uint256 pricePerSectorPerMonth' "$POREP_SRC/src/SPRegistry.sol"
assert_grep 'function setCapabilities' "$POREP_SRC/src/SPRegistry.sol"
assert_grep 'function updateAvailableSpace' "$POREP_SRC/src/SPRegistry.sol"
assert_grep 'function setPrice' "$POREP_SRC/src/SPRegistry.sol"
assert_grep 'function setPayee' "$POREP_SRC/src/SPRegistry.sol"
assert_grep 'function setDealDurationLimits' "$POREP_SRC/src/SPRegistry.sol"
assert_grep 'function create\(uint256 dealId\)' "$POREP_SRC/src/ValidatorFactory.sol"
assert_grep 'function createRail\(IERC20 token\)' "$POREP_SRC/src/Validator.sol"
assert_grep 'function getRailStatus\(\)' "$POREP_SRC/src/Validator.sol"
assert_grep 'uint8 internal constant PREPARED = 10' "$POREP_SRC/src/types/RailStatus.sol"

assert_grep 'serializeContract\(json, "DataCapEvidenceAdapter"' "$POREP_SRC/script/Deploy.s.sol"
assert_grep 'function submitEvidenceBatch' "$POREP_SRC/src/DataCapEvidenceAdapter.sol"
assert_grep 'function activateEvidence' "$POREP_SRC/src/DataCapEvidenceAdapter.sol"
assert_grep 'function refreshEvidenceStatus' "$POREP_SRC/src/DataCapEvidenceAdapter.sol"
assert_grep 'function currentEvidenceStatus' "$POREP_SRC/src/DataCapEvidenceAdapter.sol"
assert_grep 'will be implemented in the future' "$POREP_SRC/src/DataCapEvidenceAdapter.sol"

assert_not_grep 'function createOffer' "$POREP_SRC/src"
assert_not_grep 'function setPaymentToken' "$POREP_SRC/src"

assert_grep 'proposeDeal\(\(bytes32,uint256,uint256,string,address,uint32,\(uint16,uint64,uint16,uint8\)\)\)' "$ROOT/v2/steps/07_propose_deal.sh"
assert_grep 'registerProviderFor\(uint64,address,\(uint16,uint64,uint16,uint8\),uint256,uint256,address,uint32,uint32\)' "$ROOT/v2/setup/04_register_provider_and_offer.sh"
assert_grep 'setCapabilities\(uint64,\(uint16,uint64,uint16,uint8\)\)' "$ROOT/v2/setup/04_register_provider_and_offer.sh"
assert_grep 'setPrice\(uint64,uint256\)' "$ROOT/v2/setup/04_register_provider_and_offer.sh"
assert_grep 'DATACAP_EVIDENCE_ADAPTER' "$ROOT/v2/setup/02_deploy.sh"
assert_grep 'getRailStatus\(\)\(uint8\)' "$ROOT/v2/steps/12_create_rail.sh"

echo "v2 ABI contract test: ok"
