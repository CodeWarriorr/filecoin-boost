# PoRep Market Devnet Scripts

Setup and deploy [porep-market](https://github.com/fidlabs/porep-market) contracts on boost devnet.

## Prerequisites

- [Foundry](https://www.getfoundry.sh/) (`forge`, `cast`)
- [Rust](https://rust-lang.org/) (`cargo`)
- [Node.js >= v20](https://nodejs.org/) (for `steps/sign_permit.js`)
- [Go](https://go.dev/) (`go`)
- Running devnet (`make devnet/up` from repo root)
- `jq`, `xxd`, `python3`

## One-time setup

Run once after a fresh devnet (idempotent — safe to re-run after a restart):

```bash
bash setup/00_setup.sh                        # clone repos, build contracts
bash setup/01_extract_key.sh                  # extract PRIVATE_KEY_TEST, generate PRIVATE_KEY_SP → .env
bash setup/02_deploy.sh                       # deploy FilecoinPay, SPRegistry, ValidatorFactory, PoRepMarket, Client → .env
bash setup/03_deploy_allocator_and_grant_dc.sh # register MetaAllocator as verifier, grant datacap to Client
bash setup/04_register_miner.sh               # register test miners in SPRegistry
bash setup/05_deploy_token.sh                 # deploy MockUSDC, mint to deployer → .env
bash 06_setup_sli.sh                          # seed SLI oracle attestations
```

Config in `.env` (copy from `env.example` if it doesn't exist).

## Running the happy path

Run the full deal lifecycle end-to-end:

```bash
bash scenarios/happy_path.sh
```

This runs every step in order:
`Proposed → Accepted → Validator → Rail → Allocated → Claimed → Settled → Withdrawn`

Each step writes its outputs to a temporary state file so the next step can read them.

### Running steps individually

Steps live under `setup/` (one-time config) and `steps/` (deal lifecycle).
Each step reads from and writes to `.state`.

Start a fresh run:

```bash
cp state.example .state
```

To resume after a failure, re-run the failed step — `.state` already has values from previous steps.

### Required env

Both `PRIVATE_KEY_TEST` (client/deployer) and `PRIVATE_KEY_SP` (storage provider) must be set in `.env`.
`PRIVATE_KEY_SP` is needed by `steps/18_withdraw_payments.sh` to withdraw earned funds from the SP's FilecoinPay account.

## Troubleshooting

```bash
# check devnet
docker exec lotus lotus chain head

# check deploy logs
cat deploy_output.log

# check RPC
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://127.0.0.1:1234/rpc/v1
```
