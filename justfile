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
    just porep-v2-e2e-install
    bash {{scripts}}/tests/script_layout_test.sh
    find {{scripts}}/shared {{scripts}}/v1 {{scripts}}/v2/setup {{scripts}}/v2/manual {{scripts}}/tests -name '*.sh' -print0 | xargs -0 -n1 bash -n
    npm --prefix {{scripts}}/v2/e2e run typecheck
    npm --prefix {{scripts}}/v2/e2e run test:unit

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

porep-v1-devnet-up:
    POREP_MARKET_VERSION=v1 make clean docker/all
    POREP_MARKET_VERSION=v1 make devnet/up
    POREP_MARKET_VERSION=v1 just porep-v1-deploy
    POREP_MARKET_VERSION=v1 just porep-v1-devnet-check

porep-v1-devnet-check:
    POREP_MARKET_VERSION=v1 bash {{scripts}}/shared/check_deployment.sh

porep-v1-devnet-reset:
    POREP_MARKET_VERSION=v1 just porep-v1-devnet-down
    POREP_MARKET_VERSION=v1 just porep-v1-devnet-up

porep-v1-devnet-down:
    POREP_MARKET_VERSION=v1 make devnet/down

porep-v2-setup:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/setup/00_setup.sh

porep-v2-deploy:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/setup/00_setup.sh
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v1/setup/01_extract_key.sh
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/setup/02_deploy.sh
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/setup/03_grant_adapter_datacap.sh
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v1/setup/05_deploy_token.sh

porep-v2-e2e-preflight:
    npm --prefix {{scripts}}/v2/e2e run scenario -- preflight

porep-v2-e2e-install:
    POREP_MARKET_VERSION=v2 npm --prefix {{scripts}}/v2/e2e ci

porep-v2-devnet-up:
    POREP_MARKET_VERSION=v2 just porep-v2-e2e-install
    POREP_MARKET_VERSION=v2 make clean docker/all
    POREP_MARKET_VERSION=v2 make devnet/up
    POREP_MARKET_VERSION=v2 just porep-v2-deploy
    POREP_MARKET_VERSION=v2 just porep-v2-e2e-ensure-suite-funding
    POREP_MARKET_VERSION=v2 just porep-v2-devnet-check
    POREP_MARKET_VERSION=v2 just porep-v2-e2e-proposal-smoke
    POREP_MARKET_VERSION=v2 just porep-v2-e2e-validator-rail-smoke

porep-v2-devnet-check:
    POREP_MARKET_VERSION=v2 just porep-v2-e2e-preflight

porep-v2-devnet-reset:
    POREP_MARKET_VERSION=v2 just porep-v2-devnet-down
    POREP_MARKET_VERSION=v2 just porep-v2-devnet-up

porep-v2-devnet-down:
    POREP_MARKET_VERSION=v2 make devnet/down

porep-v2-e2e-typecheck:
    npm --prefix {{scripts}}/v2/e2e run typecheck
    npm --prefix {{scripts}}/v2/e2e run test:unit

porep-v2-e2e-proposal-smoke:
    npm --prefix {{scripts}}/v2/e2e run scenario -- proposal-smoke

porep-v2-e2e-validator-rail-smoke:
    npm --prefix {{scripts}}/v2/e2e run scenario -- validator-rail-smoke

porep-v2-e2e-negative-activation:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- negative-activation

porep-v2-e2e-basic-activation:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- basic-activation

porep-v2-e2e-full-available:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- full-available

porep-v2-e2e-prepare-devnet:
    npm --prefix {{scripts}}/v2/e2e run scenario -- prepare-devnet

porep-v2-e2e-ensure-suite-funding MIN_USDC="2000000000000":
    USDC_MIN_BALANCE={{MIN_USDC}} POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/setup/05_ensure_test_usdc.sh

porep-v2-e2e-deploy-readiness:
    just porep-v2-e2e-preflight
    just porep-v2-e2e-prepare-devnet
    just porep-v2-e2e-ensure-suite-funding
    just porep-v2-e2e-basic-activation
    just porep-v2-e2e-negative-activation
    just porep-v2-e2e-full-available
    just porep-v2-e2e-evidence-no-claim-activation-guard
    just porep-v2-e2e-activation-lifecycle-guards
    just porep-v2-e2e-settlement-guards
    just porep-v2-e2e-access-control-guards

porep-v2-e2e-local-devnet-p0-p1:
    just porep-v2-e2e-preflight
    just porep-v2-e2e-prepare-devnet
    just porep-v2-e2e-ensure-suite-funding
    just porep-v2-e2e-multi-claim-evidence-batches
    just porep-v2-e2e-shared-client-multi-rail-settlement
    just porep-v2-e2e-evidence-authority-guards
    just porep-v2-e2e-actor-token-guards

porep-v2-e2e-evidence-no-claim-activation-guard:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- evidence-no-claim-activation-guard

porep-v2-e2e-activation-lifecycle-guards:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- activation-lifecycle-guards

porep-v2-e2e-settlement-guards:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- settlement-guards

porep-v2-e2e-access-control-guards:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- access-control-guards

porep-v2-e2e-multi-claim-evidence-batches:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- multi-claim-evidence-batches

porep-v2-e2e-shared-client-multi-rail-settlement:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- shared-client-multi-rail-settlement

porep-v2-e2e-evidence-authority-guards:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- evidence-authority-guards

porep-v2-e2e-actor-token-guards:
    just porep-v2-e2e-prepare-devnet
    npm --prefix {{scripts}}/v2/e2e run scenario -- actor-token-guards

porep-v2-proposal-smoke:
    npm --prefix {{scripts}}/v2/e2e run scenario -- proposal-smoke

porep-v2-validator-rail-smoke:
    npm --prefix {{scripts}}/v2/e2e run scenario -- validator-rail-smoke

porep-v2-full-happy-path:
    just porep-v2-e2e-full-available

porep-v2-manual-proposal-smoke:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/manual/scenarios/proposal_smoke.sh

porep-v2-manual-validator-rail-smoke:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/manual/scenarios/validator_rail_smoke.sh

porep-v2-manual-full-happy-path:
    POREP_MARKET_VERSION=v2 bash {{scripts}}/v2/manual/scenarios/full_available_flow.sh
