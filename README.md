# Boost (PoRep Market Fork)

Fork of [filecoin-project/boost](https://github.com/filecoin-project/boost) with devnet tooling for testing [porep-market](https://github.com/fidlabs/porep-market) contracts.

## Setup

```bash
git clone git@github.com:CodeWarriorr/filecoin-boost.git
cd filecoin-boost
git submodule update --init --recursive
```

## Quick start (with [just](https://github.com/casey/just))

```bash
just up       # build images + start devnet (first time, ~30 min)
just deploy   # deploy porep-market contracts + grant datacap + register miners
just status   # check devnet health
just stop     # tear down
```

Needs Node.js 22+, Go 1.25+, Foundry. First start downloads ~2 GB proof parameters.

If on Apple Silicon and you hit FFI issues: `make clean docker/all ffi_from_source=1`.

## Manual steps

```bash
make clean docker/all   # build
make devnet/up          # start
make devnet/down        # stop
```

See [scripts/porep-market/](scripts/porep-market/README.md) for individual deploy scripts.

## SP Tools

Scripts for querying deal state on behalf of a Storage Provider organization.
Located in [`scripts/porep-market/SPTools/`](scripts/porep-market/SPTools/).

`sp_deals.sh` shows all deals (Proposed / Accepted / Completed) for an SP organization. For completed deals, also fetches Allocation IDs from the client smart contract.

Requires devnet running and `.env` with `POREP_MARKET` and `CLIENT_CONTRACT`.

```bash
# uses ORGANIZATION from .env (set by setup/06_prepare_operator.sh)
bash scripts/porep-market/SPTools/sp_deals.sh

# or pass address explicitly
bash scripts/porep-market/SPTools/sp_deals.sh 0xOrgAddress
```

The organization address is the SP's registered wallet — recorded on-chain when `proposeDeal()` is called. It is **not** the client/payer address.

Individual scripts are also available if you need to query a single state:

```bash
bash scripts/porep-market/SPTools/get_deals_proposed.sh [org_address]
bash scripts/porep-market/SPTools/get_deals_accepted.sh [org_address]
bash scripts/porep-market/SPTools/get_deals_completed.sh [org_address]
```

To fetch Allocation IDs for a specific deal:

```bash
bash scripts/porep-market/SPTools/get_allocation_ids_per_deal.sh [deal_id]
```

`sp_deals.sh` combines all of the above into a single call.

## Upstream

[filecoin-project/boost](https://github.com/filecoin-project/boost) | [docs](https://boost.filecoin.io)

## License

Dual-licensed under [MIT](./LICENSE-MIT) + [Apache 2.0](./LICENSE-APACHE).
