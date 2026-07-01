scripts := "scripts/porep-market"

build:
    make clean docker/all

up: build start

start:
    make devnet/up

stop:
    make devnet/down

down: stop

# deploy porep-market contracts to running devnet
deploy:
    bash {{scripts}}/setup/00_setup.sh
    bash {{scripts}}/setup/01_extract_key.sh
    bash {{scripts}}/setup/02_deploy.sh
    bash {{scripts}}/setup/03_deploy_allocator_and_grant_dc.sh
    bash {{scripts}}/setup/04_register_miner.sh
    bash {{scripts}}/setup/05_deploy_token.sh
    bash {{scripts}}/setup/06_setup_sli.sh
    bash {{scripts}}/setup/06_prepare_operator.sh

deposit-and-approve-operator AMOUNT="1000":
    bash {{scripts}}/steps/11_deposit_and_approve_operator.sh {{AMOUNT}}

# check devnet status
status:
    @docker exec lotus lotus chain head && echo "devnet: ok" || echo "devnet: down"
    @docker exec boost boost status 2>/dev/null | head -5 || true

logs:
    docker compose -f docker/devnet/docker-compose.yaml logs -f

prepare-operator:
    bash {{scripts}}/setup/06_prepare_operator.sh

generate-piece:
    GENERATE_PIECE=1 bash {{scripts}}/setup/07_generate_piece.sh

make-allocation:
    bash {{scripts}}/steps/13_make_allocation.sh

import-piece:
    bash {{scripts}}/steps/14_import_piece.sh

wait-for-claim:
    bash {{scripts}}/steps/16_wait_for_claim.sh

modify-rail-payment VALIDATOR_ADDRESS RAIL_ID:
    bash {{scripts}}/steps/15_modify_rail_payment.sh {{VALIDATOR_ADDRESS}} {{RAIL_ID}}

calculate-withdrawal RAIL_ID:
    bash {{scripts}}/steps/17_settle_rail.sh {{RAIL_ID}}

rail-termination VALIDATOR_ADDRESS RAIL_ID:
    bash {{scripts}}/steps/19_rail_termination.sh {{VALIDATOR_ADDRESS}} {{RAIL_ID}}

withdraw-payments AMOUNT:
    bash {{scripts}}/steps/18_withdraw_payments.sh {{AMOUNT}}

porep-script-check:
    bash {{scripts}}/tests/script_layout_test.sh
    bash {{scripts}}/tests/v2_abi_contract_test.sh
    find {{scripts}}/shared {{scripts}}/v1 {{scripts}}/v2 {{scripts}}/tests -name '*.sh' -print0 | xargs -0 -n1 bash -n

porep-v1-deploy:
    POREP_MARKET_VERSION=v1 bash {{scripts}}/v1/setup/00_setup.sh
    POREP_MARKET_VERSION=v1 bash {{scripts}}/v1/setup/01_extract_key.sh
    POREP_MARKET_VERSION=v1 bash {{scripts}}/v1/setup/02_deploy.sh
    POREP_MARKET_VERSION=v1 bash {{scripts}}/v1/setup/03_deploy_allocator_and_grant_dc.sh
    POREP_MARKET_VERSION=v1 bash {{scripts}}/v1/setup/04_register_miner.sh
    POREP_MARKET_VERSION=v1 bash {{scripts}}/v1/setup/05_deploy_token.sh
    POREP_MARKET_VERSION=v1 bash {{scripts}}/v1/setup/06_setup_sli.sh
    POREP_MARKET_VERSION=v1 bash {{scripts}}/v1/setup/06_prepare_operator.sh

porep-v1-happy-path:
    POREP_MARKET_VERSION=v1 bash {{scripts}}/v1/scenarios/happy_path.sh

porep-v2-setup:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/setup/00_setup.sh

porep-v2-deploy:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/setup/00_setup.sh
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v1/setup/01_extract_key.sh
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/setup/02_deploy.sh
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v1/setup/05_deploy_token.sh

porep-v2-proposal-smoke:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/scenarios/proposal_smoke.sh

porep-v2-validator-rail-smoke:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/scenarios/validator_rail_smoke.sh

porep-v2-full-happy-path:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/scenarios/full_happy_path_blocked.sh
