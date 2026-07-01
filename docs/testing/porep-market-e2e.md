# PoRep Market E2E Test Results

> Current script routing: this page records a 2026-03-25 V1-era run. Use
> `scripts/porep-market/v1/` for maintenance tests against PoRep Market branch
> `v1`, and `scripts/porep-market/v2/` for current tests against branch `main`.
> V2 uses `DataCapEvidenceAdapter`, split deal getters, and accepted state `20`.
> Run `just porep-script-check` before local Boost/devnet execution.

**Date:** 2026-03-25
**Branch:** porep-market `main` @ `7456835`
**Environment:** boost devnet (docker-compose)
**Triggered by:** Switch from `fix-deploy-order` to `main`

## Deployed Contracts

| Contract | Address |
|----------|---------|
| PoRepMarket | `0x5f0Ea33C3eC17cc77FA2f49657e44CCB267c0062` |
| Client | `0x2d5eb74633EA809Bb064A0139c8022415f63B504` |
| SPRegistry | `0xe1532a0ee327e7E2254812ec57FF0D2883A30aA8` |
| ValidatorFactory | `0xdc6d9C137aE1dBD2EaB38588604Adb6704056041` |
| SLIOracle | `0x686317765959753eC31E72a48030aD6e453D21e2` |
| SLIScorer | `0x8c90A3B80EFf7a97F3642a5b434eB916d206fA92` |
| MetaAllocator | `0x874bE1C5D20Af2923f963ce9ad861ad9532B641A` |
| FilecoinPay | `0x4e31EFdf7B7C9D7E56211398ba00Bb3Db36B87cE` |
| Deployer | `0x6364aB7812DE4531f798B1BFfCEC35987a1510C6` |

## Test Results Summary

| ID | Category | Test | Status | Notes |
|----|----------|------|--------|-------|
| T01 | Deploy | All contracts have bytecode | PASS | All 8 contracts verified (263+ chars each) |
| T02 | Deploy | PoRepMarket.MAX_DEAL_DURATION_DAYS == 1278 | PASS | |
| T03 | Deploy | Admin role set correctly on all contracts | PASS | All 6 return true for deployer |
| T04 | Deploy | Deploy JSON confirms wiring | PASS | All proxy+impl addresses populated |
| T05 | Deploy | ValidatorFactory.getBeacon returns non-zero | PASS | |
| T06 | Deploy | SPRegistry MARKET_ROLE + OPERATOR_ROLE | PASS | Both correctly granted |
| T07 | Deals | proposeDeal with valid params | PASS | Status 0x1, DealProposalCreated event |
| T08 | Deals | getDealProposal returns correct data | PASS | dealId=1, provider=1000, state=0(Proposed) |
| T09 | Deals | proposeDeal reverts for impossible requirements | PASS | `NoProviderFoundForDeal` |
| T10a | Deals | proposeDeal reverts: duration=0 | PASS | `InvalidDealDuration` |
| T10b | Deals | proposeDeal reverts: duration=1279 | PASS | `InvalidDealDuration` |
| T10c | Deals | proposeDeal reverts: duration=45 (not %30) | PASS | `InvalidDealDuration` |
| T11 | Deals | acceptDeal by deployer (has admin role) | PASS | State changed 0→1 (Proposed→Accepted) |
| T12 | Deals | rejectDeal by client | PASS | State changed 0→3 (Proposed→Rejected) |
| T13 | Deals | getDealProposal returns correct post-accept state | PASS | Deal 1: state=1(Accepted), Deal 2: state=3(Rejected) |
| T14 | Deals | getCompletedDeals returns empty initially | PASS | Returns empty array |

## Issues Found

### ISSUE-1: Deploy.s.sol SPRegistry ordering (FIXED on main @ `c8cdeb4`)

**Severity:** BLOCKER
**Status:** FIXED (upstream merged)
**Commit:** Part of `c8cdeb4` [Fil 1343] upgrader script

On prior main (`040917c`), `Deploy.s.sol` deployed SPRegistry AFTER PoRepMarket, passing `address(0)` as SPRegistry to `PoRepMarket.initialize()`. This caused `proposeDeal()` to revert because `getProviderForDeal()` called `address(0)`.

Your local commit `129333e` (2026-03-17) fixed this by reordering. The fix is now upstream.

### ISSUE-2: Deploy.s.sol PRIVATE_KEY rename

**Severity:** MINOR (script compat)
**Status:** FIXED (in our 02_deploy.sh)

`Deploy.s.sol` changed `vm.envUint("PRIVATE_KEY_TEST")` → `vm.envUint("PRIVATE_KEY")`. Our `02_deploy.sh` now exports `PRIVATE_KEY="$PRIVATE_KEY_TEST"`.

### ISSUE-3: registerProviderFor signature changed

**Severity:** MINOR (script compat)
**Status:** FIXED (in our 04_register_miner.sh)

`registerProviderFor` gained a `payee` address parameter. `pricePerSector` renamed to `pricePerSectorPerMonth`. Updated call signature and pass deployer as payee.

### ISSUE-4: DealState enum changed

**Severity:** INFO
**Status:** N/A (no script impact)

`None` value removed from `DealState` enum. New mapping:
- 0=Proposed, 1=Accepted, 2=Completed, 3=Rejected, 4=Terminated

(Previously: 0=None, 1=Proposed, 2=Accepted, 3=Completed, 4=Rejected, 5=Terminated)

## Changes Made to Boost Scripts

| File | Change |
|------|--------|
| `00_setup.sh:7` | Default branch `fix-deploy-order` → `main` |
| `02_deploy.sh:33` | Removed `export ALLOCATOR="$DEPLOYER"` (no longer needed) |
| `02_deploy.sh:33` | Added `export PRIVATE_KEY="$PRIVATE_KEY_TEST"` |
| `04_register_miner.sh:29` | Updated `registerProviderFor` signature (added payee param) |
| `env.example:5` | Default branch `fix-deploy-order` → `main` |
| `README.md:5` | Removed "main is broken" note |

## Reliability Notes

- FEVM devnet transactions need ~15s for confirmation. Always `sleep 15` between send and read.
- `cast call` (static calls) return immediately and reflect latest state.
- `cast send --json` is the reliable way to check tx status (`.status == "0x1"` = success).
- Decoded struct output via `cast call` with full return type signature works well for verification.
