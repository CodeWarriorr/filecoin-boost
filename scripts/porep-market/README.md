# PoRep Market Devnet Scripts

Setup and test PoRep Market contracts on the Boost devnet.

The versioned entry points are:

- `v1/` - deprecated maintenance scripts for PoRep Market branch `v1`.
- `v2/` - current scripts for PoRep Market branch `main`.
- `shared/` - environment, state, transaction, and getter helpers used by both versions.

The legacy top-level `setup/`, `steps/`, and `scenarios/` directories are kept for compatibility. New work should use the versioned paths or the `just` targets.

## Configuration

Copy `env.example` to `.env` and set the private keys needed by your local devnet. Do not commit `.env`.

Version and checkout keys:

```bash
POREP_MARKET_VERSION=v2
POREP_MARKET_BRANCH=
POREP_MARKET_V1_BRANCH=v1
POREP_MARKET_V2_BRANCH=main
POREP_MARKET_DIR=
```

`POREP_MARKET_BRANCH` is an explicit override. Leave it empty to use `POREP_MARKET_V1_BRANCH` or `POREP_MARKET_V2_BRANCH` based on `POREP_MARKET_VERSION`.

`POREP_MARKET_DIR` can point at a local sibling checkout or worktree. Leave it empty to use a version-specific script checkout: `scripts/porep-market/porep-market-v1` for V1 or `scripts/porep-market/porep-market-v2` for V2.

Version-specific deployed address keys:

```bash
CLIENT_CONTRACT=              # V1 only
DATACAP_EVIDENCE_ADAPTER=     # V2 only
```

## V2

V2 is the default target. Current `../2_porep_market/main` supports:

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

Run the V2 setup/deploy/proposal smoke against a running devnet:

```bash
just porep-v2-deploy
just porep-v2-proposal-smoke
just porep-v2-validator-rail-smoke
```

The V2 full happy path is intentionally blocked in:

```bash
just porep-v2-full-happy-path
```

That script exits `2` and names the blocker: current `DataCapEvidenceAdapter.submitEvidenceBatch()` is present, but `activateEvidence`, `refreshEvidenceStatus`, and `currentEvidenceStatus` still return dummy zero values and are marked for future implementation in the contract.

## V1

V1 remains runnable under the maintenance surface:

```bash
just porep-v1-deploy
just porep-v1-happy-path
```

V1 keeps the old `Client` allocation path, old tuple-shaped `proposeDeal`, `acceptDeal`, compact state assertions, and `getDealProposal` decoding. It should run against PoRep Market branch `v1` unless `POREP_MARKET_BRANCH` is set.

## Prerequisites

- Foundry (`forge`, `cast`)
- Rust (`cargo`)
- Node.js >= v20
- Go
- Running devnet (`make devnet/up` from repo root)
- `jq`, `xxd`, `python3`

## Troubleshooting

```bash
docker exec lotus lotus chain head
cat scripts/porep-market/v2/setup/deploy_output.log
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://127.0.0.1:1234/rpc/v1
```
