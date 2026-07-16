# Boost (PoRep Market Fork)

Fork of [filecoin-project/boost](https://github.com/filecoin-project/boost) with devnet tooling for testing [porep-market](https://github.com/fidlabs/porep-market) contracts.

## Setup

```bash
git clone git@github.com:CodeWarriorr/filecoin-boost.git
cd filecoin-boost
git submodule update --init --recursive
```

## Versioned tooling devnets

`just deploy` is the legacy, unversioned deployment surface. Use a versioned devnet for all new work; V2 is recommended.

### V2 (recommended)

```bash
just porep-v2-devnet-up
just porep-v2-devnet-check
just porep-v2-devnet-down
```

### V1 (maintenance only)

```bash
just porep-v1-devnet-up
just porep-v1-devnet-check
just porep-v1-devnet-down
```

Both `*-devnet-up` targets rebuild the images, start the devnet with its existing named-volume state when present, and deploy the selected PoRep Market version. They do not clear existing chain state. Both `*-devnet-down` and `*-devnet-reset` are destructive: they remove the named volumes and invalidate every address from the prior local chain. Reset then starts and deploys a new chain.

Needs Node.js 22+, Go 1.25+, Foundry. First start downloads ~2 GB proof parameters.

If on Apple Silicon and you hit FFI issues: `make clean docker/all ffi_from_source=1`.

## Manual steps

```bash
make clean docker/all   # build
make devnet/up          # start
make devnet/down        # stop
```

See [scripts/porep-market/](scripts/porep-market/README.md) for individual deploy scripts.

## SP Tools (V1 only)

The SP query scripts support V1 only. They are under [`scripts/porep-market/v1/SPTools/`](scripts/porep-market/v1/SPTools/) and read the V1 public contract addresses from `scripts/porep-market/.env.v1`.

`sp_deals.sh` shows all deals (Proposed / Accepted / Completed) for an SP organization. For completed deals, also fetches Allocation IDs from the client smart contract.

Requires a running V1 devnet and `.env.v1` with `POREP_MARKET` and `CLIENT_CONTRACT`. The setup scripts create that file; do not print or share its private-key lines.

```bash
# uses ORGANIZATION from .env.v1 (set by v1/setup/06_prepare_operator.sh)
bash scripts/porep-market/v1/SPTools/sp_deals.sh

# or pass address explicitly
bash scripts/porep-market/v1/SPTools/sp_deals.sh 0xOrgAddress
```

The organization address is the SP's registered wallet — recorded on-chain when `proposeDeal()` is called. It is **not** the client/payer address.

Individual scripts are also available if you need to query a single state:

```bash
bash scripts/porep-market/v1/SPTools/get_deals_proposed.sh [org_address]
bash scripts/porep-market/v1/SPTools/get_deals_accepted.sh [org_address]
bash scripts/porep-market/v1/SPTools/get_deals_completed.sh [org_address]
```

To fetch Allocation IDs for a specific deal:

```bash
bash scripts/porep-market/v1/SPTools/get_allocation_ids_per_deal.sh [deal_id]
```

`sp_deals.sh` combines all of the above into a single call.

There is no V2 SP dashboard in this repository.

For V2 tooling, connect to `http://127.0.0.1:1234/rpc/v1` and read only the public address keys from `scripts/porep-market/.env.v2`: `POREP_MARKET`, `DATACAP_EVIDENCE_ADAPTER`, `SP_REGISTRY`, `VALIDATOR_FACTORY`, `FILECOIN_PAY`, `SLI_ORACLE`, `META_ALLOCATOR`, and `USDC_TOKEN`. The pinned PoRepMarket artifact is `scripts/porep-market/porep-market-v2-803942a5f439/out/PoRepMarket.sol/PoRepMarket.json`. See [the V2 script and ABI documentation](scripts/porep-market/README.md#abi-locations-and-test-matrix) for the effective-ref path rule and available TypeScript scenarios.

## Upstream

[filecoin-project/boost](https://github.com/filecoin-project/boost) | [docs](https://boost.filecoin.io)

## License

Dual-licensed under [MIT](./LICENSE-MIT) + [Apache 2.0](./LICENSE-APACHE).
