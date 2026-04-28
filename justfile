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
