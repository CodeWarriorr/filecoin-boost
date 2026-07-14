# PoRep Market Devnet Scripts

Setup and test PoRep Market contracts on the Boost devnet.

The versioned entry points are:

- `v1/` - deprecated maintenance scripts for PoRep Market branch `v1`.
- `v2/` - current scripts for PoRep Market branch `main`.
- `shared/` - environment, state, transaction, and getter helpers used by both versions.

The legacy top-level `setup/`, `steps/`, and `scenarios/` directories are kept for compatibility. New work should use the versioned paths or the `just` targets. The root `just deploy` target is legacy and unversioned.

## Clean-clone lifecycle

Use V2 for new work. Both `*-devnet-up` targets rebuild the images, start the containers with the existing named-volume state when present, and deploy the selected contracts. They do not clear chain state. Both `*-devnet-down` targets remove the named volumes and invalidate every deployed address from that chain. The `*-devnet-reset` targets run destructive down followed by up, so they also invalidate prior addresses.

```bash
git clone git@github.com:CodeWarriorr/filecoin-boost.git
cd filecoin-boost
git submodule update --init --recursive

just porep-v2-devnet-up
just porep-v2-devnet-check
just porep-v2-devnet-down

# V1 maintenance surface
just porep-v1-devnet-up
just porep-v1-devnet-check
just porep-v1-devnet-down
```

The local RPC is `http://127.0.0.1:1234/rpc/v1` and the fixed local chain ID is `31415926`. V1 writes addresses to `.env.v1`; V2 writes addresses to `.env.v2`.

To discover public deployed addresses without printing private-key lines, run:

```bash
just porep-v1-devnet-check
just porep-v2-devnet-check
```

## Configuration

Copy `env.v1.example` to `.env.v1` for V1 or `env.v2.example` to `.env.v2` for V2, then set the private keys needed by your local devnet. Do not commit these environment files.

Version and checkout keys:

```bash
POREP_MARKET_VERSION=v2
POREP_MARKET_V1_REF=62754c6ceafe0e9f6eae926297633029c95d2589
POREP_MARKET_V2_REF=803942a5f439e0a588da245727197ca22546bb1f
POREP_MARKET_DIR=
```

Shell setup and the TypeScript harness share `POREP_MARKET_DIR` as the only explicit contract-checkout override. When it is unset, both deterministically select the managed, pin-specific checkout derived from the effective version ref's first 12 characters. With the shipped pins, those paths are `scripts/porep-market/porep-market-v1-62754c6ceafe` and `scripts/porep-market/porep-market-v2-803942a5f439`; overriding a version ref changes the matching suffix.

Setup requires the checkout `HEAD` to equal the effective version ref and rejects tracked or untracked source changes before `forge build` or deployment. Generated `deployments/devnet/*.json` records are allowed so a completed deployment can be checked or repeated. An explicit `POREP_MARKET_DIR` is never cleaned or reset. To use another revision, override both `POREP_MARKET_V1_REF` or `POREP_MARKET_V2_REF` and `POREP_MARKET_DIR`; setup fails if only the directory points at another commit.

Version-specific deployed address keys:

```bash
CLIENT_CONTRACT=              # V1 only
DATACAP_EVIDENCE_ADAPTER=     # V2 only
```

## V2

V2 is the default target. The pinned V2 contract revision used by default setup supports:

- deploy output extraction for `DataCapEvidenceAdapter`
- bounded `DataCapEvidenceAdapter.submitEvidenceBatch()` ABI coverage
- provider registration through `SPRegistry.registerProviderFor(uint64,address,(uint16,uint64,uint16,uint8),uint256,uint256,address,uint32,uint32)`
- `PoRepMarket.proposeDeal((bytes32,uint256,uint256,string,address,uint32,(uint16,uint64,uint16,uint8)))`
- split deal getters: `getDeal`, `getDealData`, `getDealTerms`, `getDealCapacity`, `getDealPayment`, and `getDealSLIs`
- accepted-state assertion with V2 state code `20`

Run the lightweight checks:

```bash
just porep-script-check
```

Run individual V2 setup/deploy and TypeScript E2E scenarios against a running devnet:

```bash
just porep-v2-deploy
just porep-v2-e2e-proposal-smoke
just porep-v2-e2e-validator-rail-smoke
```

The V2 lifecycle target runs the E2E install, deploy, suite funding, strict preflight, proposal smoke, and validator-rail smoke in that order:

```bash
just porep-v2-devnet-up
```

The TypeScript V2 full scenario runs through:

```bash
just porep-v2-full-happy-path
```

The retained Bash implementation is explicitly manual/legacy and remains available when needed:

```bash
just porep-v2-manual-proposal-smoke
just porep-v2-manual-validator-rail-smoke
just porep-v2-manual-full-happy-path
```

## V1

V1 remains runnable under the maintenance surface:

```bash
just porep-v1-deploy
just porep-v1-happy-path
```

Its complete lifecycle is:

```bash
just porep-v1-devnet-up
just porep-v1-devnet-reset
```

V1 keeps the old `Client` allocation path, old tuple-shaped `proposeDeal`, `acceptDeal`, compact state assertions, and `getDealProposal` decoding. It uses `POREP_MARKET_V1_REF` unless `POREP_MARKET_DIR` points to an explicit checkout.

## Prerequisites

- Foundry (`forge`, `cast`)
- Rust (`cargo`)
- Node.js >= v20
- Go
- Running devnet (`make devnet/up` from repo root)
- `jq`, `xxd`

## ABI locations and test matrix

PoRep Forge ABI artifacts are under the effective checkout's `out/` directory. With the shipped pins, the PoRepMarket ABI paths are `scripts/porep-market/porep-market-v1-62754c6ceafe/out/PoRepMarket.sol/PoRepMarket.json` and `scripts/porep-market/porep-market-v2-803942a5f439/out/PoRepMarket.sol/PoRepMarket.json`; use the effective-ref suffix when a pin is overridden. FilecoinPay's ABI remains `scripts/porep-market/filecoin-pay/out/FilecoinPayV1.sol/FilecoinPayV1.json`.

Run the focused smoke checks after a V2 deploy:

```bash
just porep-v2-e2e-proposal-smoke
just porep-v2-e2e-validator-rail-smoke
```

Run the full local V2 matrix with:

```bash
just porep-v2-e2e-deploy-readiness
just porep-v2-e2e-local-devnet-p0-p1
```

## Troubleshooting

```bash
docker exec lotus lotus chain head
cat scripts/porep-market/v2/setup/deploy_output.log
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://127.0.0.1:1234/rpc/v1
```
