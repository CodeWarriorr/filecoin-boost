#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file() {
    local path="$1"
    [ -f "$path" ] || fail "missing file: ${path#$REPO_ROOT/}"
}

assert_dir() {
    local path="$1"
    [ -d "$path" ] || fail "missing directory: ${path#$REPO_ROOT/}"
}

assert_grep() {
    local pattern="$1" path="$2"
    rg -q "$pattern" "$path" || fail "missing pattern '$pattern' in ${path#$REPO_ROOT/}"
}

assert_not_grep() {
    local pattern="$1" path="$2"
    if rg -q "$pattern" "$path"; then
        fail "unexpected pattern '$pattern' in ${path#$REPO_ROOT/}"
    fi
}

assert_dir "$ROOT/v1/setup"
assert_dir "$ROOT/v1/steps"
assert_dir "$ROOT/v1/scenarios"
assert_dir "$ROOT/v2/setup"
assert_dir "$ROOT/v2/steps"
assert_dir "$ROOT/v2/scenarios"

assert_file "$ROOT/shared/_common.sh"
assert_file "$ROOT/v1/setup/00_setup.sh"
assert_file "$ROOT/v1/setup/02_deploy.sh"
assert_file "$ROOT/v1/scenarios/happy_path.sh"
assert_file "$ROOT/v2/setup/00_setup.sh"
assert_file "$ROOT/v2/setup/02_deploy.sh"
assert_file "$ROOT/v2/setup/04_register_provider_and_offer.sh"
assert_file "$ROOT/v2/steps/07_propose_deal.sh"
assert_file "$ROOT/v2/steps/10_deploy_validator.sh"
assert_file "$ROOT/v2/steps/11_deposit_and_approve_operator.sh"
assert_file "$ROOT/v2/steps/12_create_rail.sh"
assert_file "$ROOT/v2/scenarios/proposal_smoke.sh"
assert_file "$ROOT/v2/scenarios/validator_rail_smoke.sh"
assert_file "$ROOT/v2/scenarios/full_happy_path_blocked.sh"
assert_file "$ROOT/tests/v2_abi_contract_test.sh"

assert_grep '^POREP_MARKET_VERSION=v2$' "$ROOT/env.example"
assert_grep '^POREP_MARKET_V1_BRANCH=v1$' "$ROOT/env.example"
assert_grep '^POREP_MARKET_V2_BRANCH=main$' "$ROOT/env.example"
assert_grep '^POREP_MARKET_DIR=$' "$ROOT/env.example"
assert_grep '^DATACAP_EVIDENCE_ADAPTER=$' "$ROOT/env.example"

assert_grep 'porep-market-v1' "$ROOT/shared/_common.sh"
assert_grep 'porep-market-v2' "$ROOT/shared/_common.sh"
assert_grep 'POREP_MARKET_V1_BRANCH' "$ROOT/v1/setup/00_setup.sh"
assert_grep 'POREP_MARKET_V2_BRANCH' "$ROOT/v2/setup/00_setup.sh"
assert_grep 'DataCapEvidenceAdapter' "$ROOT/v2/setup/02_deploy.sh"
assert_grep 'DATACAP_EVIDENCE_ADAPTER' "$ROOT/v2/setup/02_deploy.sh"
assert_grep 'registerProviderFor\(uint64,address,\(uint16,uint64,uint16,uint8\),uint256,uint256,address,uint32,uint32\)' "$ROOT/v2/setup/04_register_provider_and_offer.sh"
assert_grep 'setCapabilities\(uint64,\(uint16,uint64,uint16,uint8\)\)' "$ROOT/v2/setup/04_register_provider_and_offer.sh"
assert_grep 'setPrice\(uint64,uint256\)' "$ROOT/v2/setup/04_register_provider_and_offer.sh"
assert_grep 'setDealDurationLimits\(uint64,uint32,uint32\)' "$ROOT/v2/setup/04_register_provider_and_offer.sh"
assert_grep 'no createOffer or setPaymentToken API' "$ROOT/v2/setup/04_register_provider_and_offer.sh"
assert_grep 'proposeDeal\(\(bytes32,uint256,uint256,string,address,uint32,\(uint16,uint64,uint16,uint8\)\)\)' "$ROOT/v2/steps/07_propose_deal.sh"
assert_grep 'EXPECTED_DURATION_EPOCHS' "$ROOT/v2/steps/07_propose_deal.sh"
assert_grep 'reservedBytes mismatch' "$ROOT/v2/steps/07_propose_deal.sh"
assert_grep 'paymentToken mismatch' "$ROOT/v2/steps/07_propose_deal.sh"
assert_grep 'get_v2_deal_field "\$DEAL_ID" 6' "$ROOT/v2/steps/10_deploy_validator.sh"
assert_grep 'depositWithPermitAndApproveOperator' "$ROOT/v2/steps/11_deposit_and_approve_operator.sh"
assert_grep 'getRailStatus\(\)\(uint8\)' "$ROOT/v2/steps/12_create_rail.sh"
assert_not_grep 'acceptDeal' "$ROOT/v2/scenarios/proposal_smoke.sh"
assert_not_grep 'acceptDeal' "$ROOT/v2/scenarios/validator_rail_smoke.sh"

assert_grep '^porep-v1-deploy:' "$REPO_ROOT/justfile"
assert_grep '^porep-v1-happy-path:' "$REPO_ROOT/justfile"
assert_grep '^porep-v2-deploy:' "$REPO_ROOT/justfile"
assert_grep '^porep-v2-proposal-smoke:' "$REPO_ROOT/justfile"
assert_grep '^porep-v2-validator-rail-smoke:' "$REPO_ROOT/justfile"
assert_grep '^porep-script-check:' "$REPO_ROOT/justfile"

echo "script layout test: ok"
