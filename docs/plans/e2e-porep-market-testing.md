# E2E Testing PoRep Market Contracts via Boost Devnet

## Overview

The Boost repository provides a complete local Filecoin network (devnet) capable of real deal-making, sector sealing, and storage proving. This can be used to end-to-end test the PoRep Market contracts (`../2_porep_market/`) against real Filecoin actors (VerifReg, DataCap, Miner) instead of mocks.

## Boost Devnet Capabilities

### What It Provides

| Component | Details |
|-----------|---------|
| Lotus Full Node | Complete Filecoin blockchain, 100ms block time |
| Lotus Miner | Real sector sealing (8MiB sectors), WindowPoSt proving |
| Boost Daemon (boostd) | Markets V2 deal handling |
| Booster-HTTP | Content retrieval via HTTP |
| Booster-Bitswap | Content retrieval via Bitswap |
| YugabyteDB | Metadata backend |
| FEVM | Full EVM support with all Filecoin precompiles |
| FIL+ Setup | Verifiers, allocators, DataCap — bootstrapped automatically |

### Binaries Built

- `boostd` — main daemon
- `boost` — CLI client (deal making, allocations, claims)
- `booster-http` / `booster-bitswap` — retrieval
- `devnet` — local network launcher
- `boostx`, `migrate-lid` — utilities

### Docker Devnet Stack

```yaml
# docker/devnet/docker-compose.yaml
Services:
  lotus:          port 1234 (API), 9090 (libp2p)
  lotus-miner:    port 2345
  boost:          port 8080 (GUI), 1288 (API), 50000 (libp2p)
  booster-http:   port 7777
  booster-bitswap: port 8888
  demo-http-server: nginx for test files
  yugabytedb:     port 5433, 9000, 9042
  lotus-proxy:    nginx proxy
```

## PoRep Market Contract Dependencies on Filecoin Actors

### FEVM Precompiles Required

| Precompile | Address | Used By | Purpose |
|------------|---------|---------|---------|
| DataCap | `0xff00...0007` | Client.sol | Transfer DataCap to SP; FRC-46 receiver hook |
| VerifReg | via DataCap | Client.sol | `addVerifiedClient()`, `getClaims()` |
| MinerAPI | Per-miner | SPRegistry.sol | `isControllingAddress()` for SP ownership |
| ResolveAddress | `0xfe00...0001` | Tests | Address resolution |

All of these are **live** on any real Filecoin network, including the Boost devnet.

### PoRep Market Deal Lifecycle

```
1. Client calls PoRepMarket.proposeDeal(SLIThresholds, DealTerms, manifestLocation)
   → SPRegistry.getProviderForDeal() matches an SP
   → Deal state: Proposed (or Accepted if autoApprove)

2. SP controller calls PoRepMarket.acceptDeal(dealId)
   → Verified via MinerAPI.isControllingAddress()
   → Deal state: Accepted

3. ValidatorFactory.create() → deploys Validator proxy
   → PoRepMarket.updateValidator(dealId)
   → PoRepMarket.updateRailId(dealId, railId) — links FilecoinPay rail

4. Client calls Client.transfer(TransferParams, dealId, dealCompleted)
   → Calls VerifRegAPI.addVerifiedClient()
   → Calls DataCapAPI.transfer() with CBOR-encoded operator_data
   → operator_data contains: [[allocations], [claim_extensions]]
   → Returns allocation IDs from VerifReg
   → If dealCompleted=true → PoRepMarket.completeDeal()

5. SP claims allocations by sealing sectors containing the data
   → Allocation auto-converts to Claim on sector proving
```

### Current Test Suite (Mocks Only)

| Test File | What It Tests | Mock Strategy |
|-----------|--------------|---------------|
| PoRepMarket.t.sol | Deal lifecycle | Mocks SPRegistry, ValidatorFactory |
| Client.t.sol | DataCap transfer, CBOR | Mocks VerifReg, DataCap via `vm.etch()` |
| SPRegistry.t.sol | Provider matching | Direct (no external deps) |
| ValidatorFactory.t.sol | Beacon proxy creation | Mocks Validator |
| SLIOracle.t.sol | SLI attestations | Direct |

## DDO: The Bridge Between Contracts and Sealing

### Direct Data Onboarding (DDO)

Boost implements DDO — the mechanism for claiming allocations automatically. This is the critical bridge between PoRep Market's on-chain allocations and the miner's sealing pipeline.

### How DDO Auto-Claiming Works

```
1. Allocations created on-chain (via Client.transfer() or boost allocate)

2. Deal imported into Boost:
   boost direct-deal import --allocation-id <ID> --piece-cid <CID> --car <file>

3. Boost adds piece to sector with VerifiedAllocationKey:
   PieceActivationManifest {
     CID:  pieceCID,
     Size: pieceSize,
     VerifiedAllocationKey: {
       Client: clientActorID,
       ID:     allocationID,
     },
   }

4. Lotus-miner seals the sector (PoRep proof generation)

5. On sector proving → protocol AUTOMATICALLY claims the allocation
   No manual ClaimAllocation() message needed

6. Boost polls for claim confirmation (10 min timeout, 10s interval)
   Verifies claim sector matches expected sector
```

### Key Boost CLI Commands

```bash
# Create allocations (alternative to Client.transfer())
boost allocate --piece-info <cid>=<size> --miner <addr> --wallet <wallet>

# Import deal for sealing (triggers auto-claim on prove)
boost direct-deal import --allocation-id <ID> --piece-cid <CID> --car <file>

# List allocations
boost direct-deal list-allocations --wallet <wallet> [--miner <addr>]

# List claims (verify claiming worked)
boost list-claims <provider-address> [--expired]

# Extend claim term
boost extend-claim [--all | <ids>] --miner <addr> --term-max <epochs>
```

### DDO Deal Checkpoints (State Machine)

1. **Accepted** — Deal validated against allocation
2. **Transferred** — ComMP calculated and verified
3. **AddedPiece** — Piece added to sealing sector via `SectorAddPieceToAny()`
4. **IndexedAndAnnounced** — Published to piece directory / IPNI
5. **Complete** — Claim confirmed on chain

### Key Source Files

| File | Purpose |
|------|---------|
| `cmd/boost/direct_deal.go` (799 LOC) | CLI: allocate, list-allocations, list-claims, extend-claim |
| `storagemarket/direct_deals_provider.go` (799 LOC) | Core DDO engine: import, seal, confirm claim |
| `storagemarket/types/direct_deal.go` | DirectDeal data structures |
| `itests/ddo_test.go` (184 LOC) | Full E2E DDO test |
| `itests/framework/framework.go` (1149 LOC) | Test infrastructure (Lotus+Boost env) |
| `node/impl/boost.go:191` | BoostDirectDeal() RPC entry point |

## E2E Test Plan

### Architecture

```
Boost Devnet (Lotus + Miner + FEVM)
         │
         ├── Deploy to FEVM:
         │   ├── PoRepMarket (UUPS proxy)
         │   ├── Client (UUPS proxy)
         │   ├── SPRegistry (UUPS proxy)
         │   ├── ValidatorFactory + Validator beacon
         │   ├── FilecoinPay (from ../filecoin-pay/)
         │   └── SLIOracle + SLIScorer
         │
         ├── Setup:
         │   ├── Register devnet miner in SPRegistry
         │   ├── Grant DataCap to Client contract (via devnet verifier)
         │   └── Configure SLI thresholds
         │
         ├── Test Flow:
         │   ├── proposeDeal() → real SP matching against devnet miner
         │   ├── acceptDeal() → real MinerAPI.isControllingAddress()
         │   ├── Client.transfer() → real DataCap + VerifReg precompiles
         │   ├── Read allocation IDs from chain
         │   ├── boost direct-deal import (with allocation IDs + data)
         │   ├── Wait for sector prove → auto-claim
         │   └── Verify claims via VerifRegAPI.getClaims()
         │
         └── Validation:
             ├── CBOR encoding/decoding against real actors
             ├── FRC-46 receiver hook acceptance
             ├── Allocation → Claim lifecycle
             └── SPRegistry capacity accounting
```

### Step-by-Step

1. **Start devnet**: `make clean docker/all && make devnet/up`
2. **Deploy contracts**: `forge script script/Deploy.s.sol --rpc-url <devnet-rpc> --broadcast`
3. **Register miner**: Call `SPRegistry.registerProvider()` with devnet miner's FilActorId
4. **Fund Client**: Transfer DataCap to Client contract via devnet's FIL+ verifier
5. **Propose deal**: `PoRepMarket.proposeDeal(thresholds, terms, manifest)`
6. **Accept deal**: `PoRepMarket.acceptDeal(dealId)` from miner's control address
7. **Setup validator**: `ValidatorFactory.create()` + `updateValidator()` + `updateRailId()`
8. **Transfer DataCap**: `Client.transfer(params, dealId, true)` — creates real allocations
9. **Import into Boost**: `boost direct-deal import --allocation-id <ID> ...`
10. **Wait for seal + prove**: Sector seals, proves, allocation auto-claimed
11. **Verify**: `boost list-claims`, `VerifRegAPI.getClaims()` from contract

### What This Tests That Mocks Cannot

| Aspect | Mock Tests | E2E Tests |
|--------|-----------|-----------|
| CBOR encoding of operator_data | Hardcoded hex blobs | Real VerifReg parsing |
| DataCap transfer | Mock returns | Real FRC-46 protocol |
| Allocation creation | Simulated IDs | Real VerifReg state |
| Claim verification | Mock getClaims() | Real on-chain claims |
| MinerAPI ownership check | Stubbed true/false | Real miner actor |
| Sector padding tolerance | Unit math | Real sector sizes |

### Devnet Configuration

| Parameter | Value |
|-----------|-------|
| Sector size | 8MiB (fast for testing) |
| Block time | 100ms |
| Batch precommits | Disabled |
| Aggregate commits | Disabled |
| Wait deals delay | 20s |
| Bootstrap time | ~20 min (proof parameter download on first run) |

## External Dependencies

| Dependency | Source | Required For |
|------------|--------|-------------|
| FilecoinPay | `../filecoin-pay/` | Payment rails, lockup, streaming |
| SLIOracle data | Off-chain oracle service | SLI scoring (can mock for E2E) |
| Data manifest | HTTP server | `manifestLocation` in deal terms |

## Integration Test Reference

The existing DDO integration test (`itests/ddo_test.go`) demonstrates the complete flow:

```go
// 1. Create allocation
allocMsg := util.CreateAllocationMsg(...)
sm, err := fullNode.MpoolPushMessage(ctx, allocMsg, nil)

// 2. Import direct deal
ddParams := api.DirectDealParams{
    DealUUID:     dealUuid,
    AllocationID: allocId,
    PieceCid:     pieceCid,
    ClientAddr:   clientAddr,
    // ...
}
rej, err := boostClient.BoostDirectDeal(ctx, ddParams)

// 3. Wait for sector proving
framework.WaitForDealAddedToSector(dealUuid)

// 4. Verify allocation consumed, claim exists
allocs, _ := fullNode.StateGetAllocations(ctx, clientAddr, types.EmptyTSK)
assert.Len(t, allocs, 0) // allocation consumed
claims, _ := fullNode.StateGetClaims(ctx, minerAddr, types.EmptyTSK)
assert.Len(t, claims, 1) // claim exists
```

This same pattern applies to PoRep Market E2E testing — the contract creates the allocation, Boost handles the rest.
