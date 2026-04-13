scripts := "scripts/porep-market/setup"

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
    bash {{scripts}}/00_setup.sh
    bash {{scripts}}/01_extract_key.sh
    bash {{scripts}}/02_deploy.sh
    bash {{scripts}}/03_deploy_allocator_and_grant_dc.sh
    bash {{scripts}}/04_register_miner.sh
    bash {{scripts}}/05_deploy_token.sh
    bash {{scripts}}/06_prepare_operator.sh


deposit-and-approve-operator DEAL_ID AMOUNT="1000":
    bash {{scripts}}/deposit_and_approve_operator.sh {{DEAL_ID}} {{AMOUNT}}

# check devnet status
status:
    @docker exec lotus lotus chain head && echo "devnet: ok" || echo "devnet: down"
    @docker exec boost boost status 2>/dev/null | head -5 || true

logs:
    docker compose -f docker/devnet/docker-compose.yaml logs -f

prepare-operator:
    bash {{scripts}}/steps/prepare_operator.sh

generate-piece:
    bash {{scripts}}/steps/generate_piece.sh

make-allocation:
    bash {{scripts}}/steps/make_allocation.sh

import-piece:
    bash {{scripts}}/steps/import_piece.sh

wait-for-claim:
    bash {{scripts}}/steps/wait_for_claim.sh

modify-rail-payment VALIDATOR_ADDRESS RAIL_ID:
    bash {{scripts}}/modify_rail_payment.sh {{VALIDATOR_ADDRESS}} {{RAIL_ID}}

calculate-withdrawal RAIL_ID:
    bash {{scripts}}/trigger_settle_rail.sh {{RAIL_ID}}

rail-termination VALIDATOR_ADDRESS RAIL_ID:
    bash {{scripts}}/trigger_rail_termination.sh {{VALIDATOR_ADDRESS}} {{RAIL_ID}}

withdraw-payments AMOUNT RAIL_ID:
    bash {{scripts}}/withdraw_payments {{AMOUNT}}
