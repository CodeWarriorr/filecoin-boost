# PoRep Market V1/V2 Script Migration And V2 Tests Goal Pack

## Prompt 1 - /goal Starter

```text
/goal follow docs/goals/2026-07-01-porep-market-v1-v2-script-migration-and-v2-tests.md, keep its checklist and progress ledger updated, re-read it after resume or compaction, verify each required item from actual evidence, and only complete when every checklist item is proven
```

## Prompt 2 - Actual Execution Prompt

### Objective

Fully migrate the existing PoRep Market V1 Boost scripts and unreleased scenario tests into a V1-specific surface, make the PoRep Market script harness configurable by version and branch, prepare the V2 local Boost/devnet testing harness on `main`, and add the V2 tests that are possible against the current V2 contract implementation.

### Context Carry Forward

- Target AI/tool: Codex Goal execution in `/Users/mmach/git/1_neti/1_filecoin/boost`.
- Current Boost branch should be `main`, clean except for changes made during this goal.
- PoRep Market V1 contract code lives on branch `v1` in sibling repo `/Users/mmach/git/1_neti/1_filecoin/2_porep_market`.
- PoRep Market V2 contract code will be on branch `main` in `/Users/mmach/git/1_neti/1_filecoin/2_porep_market`.
- Existing Boost `scripts/porep-market/` scripts are V1-shaped. They expect `Client`, old tuple-shaped `proposeDeal`, `acceptDeal`, compact deal states, old `getDealProposal`, and DataCap transfer through `CLIENT_CONTRACT`.
- V2 differs materially:
  - `PoRepMarket.proposeDeal(SharedTypes.DealRequest)` takes `manifestHash`, `requestedSizeBytes`, `maxPricePer32GiBPerMonth`, `manifestLocation`, `paymentToken`, `durationDays`, and `requiredSLIs`.
  - V2 proposal auto-selects/reserves the provider and immediately stores the deal as `ACCEPTED`.
  - V2 state codes are gapped: `PROPOSED = 10`, `ACCEPTED = 20`, `ACTIVE = 30`, `FINALIZED = 40`, `REJECTED = 50`, `EXPIRED = 60`, `TERMINATED = 70`.
  - V2 deployment serializes `DataCapEvidenceAdapter`, not `Client`.
  - V2 provider setup requires `SPRegistry.registerProviderFor(uint64,address,uint256,address)`, `setPaymentToken`, `createOffer`, and offer payment rows.
  - V2 full happy path may be blocked if current `DataCapEvidenceAdapter` generic evidence activation/status methods are still placeholders. Do not fake a complete test. Prepare the harness and add passing tests up to the real implemented boundary.
- Prior durable analysis note, useful but not authoritative over live code: `/Users/mmach/mind_vault/projects/porep-market/2026-06-30-v2-local-boost-test-plan.md`.

### Context Anchors

Read these before editing:

- `scripts/porep-market/README.md` - current user-facing script instructions.
- `scripts/porep-market/env.example` - current script configuration surface.
- `scripts/porep-market/_common.sh` - shared env, state, tx, and contract-call helpers.
- `scripts/porep-market/setup/*.sh` - existing V1 setup/deploy/provider/token/SLI/Boost prep flow.
- `scripts/porep-market/steps/*.sh` - existing V1 lifecycle steps.
- `scripts/porep-market/scenarios/*.sh` - existing V1 scenario tests and unreleased scenario coverage.
- `scripts/porep-market/state.example` - shared state contract.
- `justfile` - current entry points.
- `docs/testing/porep-market-e2e.md`, `docs/plans/e2e-porep-market-testing.md`, `docs/handoff/modular-test-scripts.md`, `docs/handoff/typescript-scenario-scripting.md` - existing docs; many are V1-era and must not be treated as current V2 truth without live contract checks.
- `/Users/mmach/git/1_neti/1_filecoin/2_porep_market/AGENTS.md` - PoRep Market repo instructions.
- `/Users/mmach/git/1_neti/1_filecoin/2_porep_market/src/PoRepMarket.sol`, `src/SPRegistry.sol`, `src/DataCapEvidenceAdapter.sol`, `src/types/*.sol`, `src/interfaces/*.sol`, and `script/Deploy.s.sol` on branch `main` - V2 source of truth.
- `/Users/mmach/git/1_neti/1_filecoin/2_porep_market` branch `v1` - V1 source of truth.

Useful commands for grounding:

```bash
git status --short --branch
git -C ../2_porep_market status --short --branch
git -C ../2_porep_market branch --list main v1
rg -n "POREP_MARKET_BRANCH|CLIENT_CONTRACT|DataCapEvidenceAdapter|proposeDeal|acceptDeal|getDealProposal|registerProviderFor|createOffer|setPaymentToken" scripts/porep-market docs justfile
find scripts/porep-market -maxdepth 3 -type f | sort
```

### Scope

Allowed:

- Modify Boost repo files needed for `scripts/porep-market` V1/V2 isolation, configuration, tests, docs, and `justfile` entry points.
- Create versioned directories under `scripts/porep-market/` such as `v1/`, `v2/`, `shared/`, `tests/`, or similar if that fits the current repo style.
- Preserve and move existing V1 scripts and scenario tests rather than deleting them.
- Add small script-level tests or verification scripts for helper behavior, branch/version selection, path layout, config parsing, syntax, and V2 smoke scenarios.
- Update docs that currently describe old V1 behavior as if it were generic PoRep Market behavior.
- Add small helper functions when they remove real duplication between V1/V2 scripts.

Forbidden without explicit user approval:

- Do not run `git add`, `git commit`, `git push`, or `git rebase`; Filecoin parent instructions forbid git write operations.
- Do not delete existing scenario coverage without first proving it is duplicated in the migrated V1 surface.
- Do not edit secrets or print real private keys. Treat `scripts/porep-market/.env` as local runtime state; prefer `env.example` and generated test fixtures.
- Do not install new global packages. For Python, use `uv` or a local venv if needed. Prefer no new dependency.
- Do not publish packages, run destructive Docker cleanup, or wipe devnet state unless the user explicitly approves the exact command.
- Do not modify sibling `2_porep_market` contract source unless the user explicitly expands scope. This goal is Boost-side harness and tests.

Ask the user before:

- Deleting files instead of moving or preserving them under `v1/`.
- Adding a new test framework dependency.
- Running long or destructive devnet reset commands.
- Changing the intended branch model: V1 branch `v1`, V2 branch `main`.

### Required Design Outcomes

The final Boost script structure MUST make these things explicit and configurable:

- PoRep Market version: V1 or V2.
- V1 branch name, default `v1`.
- V2 branch name, default `main`.
- Optional local PoRep Market checkout path override for testing sibling worktrees without cloning.
- Version-specific deployed address names:
  - V1 can use `CLIENT_CONTRACT`.
  - V2 must use `DATACAP_EVIDENCE_ADAPTER` or the exact current V2 deployment key.
- Version-specific setup:
  - V1 provider registration and offer/payment model must remain V1-compatible.
  - V2 provider registration, token policy, and offer creation must match V2 live contracts.
- Version-specific state assertions:
  - V1 compact states stay in V1 only.
  - V2 gapped states stay in V2 only.
- Version-specific proposal path:
  - V1 may call old tuple `proposeDeal` and `acceptDeal`.
  - V2 must call `proposeDeal(SharedTypes.DealRequest)` and must not call `acceptDeal` in its happy path.
- Version-specific allocation path:
  - V1 may route DataCap through `Client`.
  - V2 must route implemented evidence/allocation calls through `DataCapEvidenceAdapter` where current contracts support it.

### Execution Checklist

- [x] Re-read this file and initialize the progress ledger with the current time, branch, and first evidence commands.
- [x] Confirm Boost repo is on `main`; record `git status --short --branch`.
- [x] Confirm sibling PoRep Market has `main` and `v1`; record `git -C ../2_porep_market branch --list main v1` and current status. Do not modify sibling repo.
- [x] Inventory every current `scripts/porep-market` setup, step, scenario, helper, example, state, and docs file before editing. Record which are V1-only, shared, or V2-targeted.
- [x] Identify any unreleased or uncommitted script/scenario tests in the current Boost checkout. Preserve them under the V1 surface if they are V1-shaped, and include them in the migrated runnable entry points.
- [x] Choose and implement a focused versioned layout. Prefer preserving existing V1 behavior under `scripts/porep-market/v1/` and introducing V2 under `scripts/porep-market/v2/`, with shared helpers only where behavior is genuinely common.
- [x] Add configuration keys to `scripts/porep-market/env.example` and shared helpers. Required defaults: `POREP_MARKET_VERSION=v2`, `POREP_MARKET_V1_BRANCH=v1`, `POREP_MARKET_V2_BRANCH=main`, plus a local checkout override key if useful.
- [x] Update setup/checkout logic so V1 uses branch `v1` and V2 uses branch `main`, while preserving the existing repo URL override.
- [x] Update deployment extraction so V1 extracts `Client` and V2 extracts `DataCapEvidenceAdapter`; keep the V1 `CLIENT_CONTRACT` env key V1-only and add the V2 adapter env key.
- [x] Move or wrap V1 setup, steps, scenarios, and SPTools so existing V1 lifecycle tests still have runnable commands.
- [x] Add V2 setup scripts for provider registration, payment-token policy, offer creation, deploy output extraction, and proposal smoke path against live V2 ABIs. Blocked part: live `../2_porep_market/main` has no `createOffer` or `setPaymentToken`; V2 setup documents and tests that provider matching is current price/capacity based.
- [x] Add V2 helper decoders for split getters: `getDeal`, `getDealData`, `getDealTerms`, `getDealCapacity`, `getDealPayment`, and `getDealSLIs`.
- [x] Add V2 scenario tests that can pass against current V2:
  - deploy/address extraction smoke
  - provider registration and offer setup smoke
  - proposal smoke with `manifestHash`, `paymentToken`, selected offer, reserved bytes, accepted state `20`, payment snapshot, and no `acceptDeal`
  - validator creation / prepared rail smoke if current V2 contracts and local FilecoinPay path support it
  - DataCapEvidenceAdapter allocation/evidence smoke only to the implemented boundary
- [x] For V2 flows that cannot pass because V2 contract functionality is missing, add skipped/blocked scenario wrappers or docs that fail closed with a clear message and exact contract/function blocker. Do not silently pass fake tests.
- [x] Update `justfile` with clear versioned entry points, for example `porep-v1-deploy`, `porep-v1-happy-path`, `porep-v2-deploy`, `porep-v2-proposal-smoke`, and script test targets. Use names that match the final layout.
- [x] Update `scripts/porep-market/README.md` and relevant docs so V1 and V2 instructions are separate and current. Mark V1 as deprecated/maintenance, not default.
- [x] Add or update automated script checks. At minimum run `bash -n` over all shell scripts under the new versioned surfaces and add a target or script that does this repeatably.
- [x] Run focused verification after each major phase and record the command/result in this file.
- [x] Run final verification gates and update the progress ledger.
- [x] Final audit: prove every required outcome from actual files and command output before claiming completion. Live V2 deploy, proposal smoke, and validator/prepared-rail smoke were run against the local devnet. The full happy path remains intentionally blocked at the dummy `DataCapEvidenceAdapter` activation/status boundary, and Boost HTTP health is separately blocked by a reproducible local `boostd-data` Yugabyte migration failure.

### Suggested Implementation Phases

Phase 1: Inventory and Layout

- Produce a short internal map of current files and classify V1/shared/V2.
- Move or wrap V1 scripts without changing behavior.
- Keep compatibility entry points if existing users run `scripts/porep-market/scenarios/happy_path.sh`; if you keep wrappers, make them explicit about default version.

Phase 2: Config and Branch Selection

- Centralize branch/version defaults in `env.example` and `_common.sh` or a new shared helper.
- Use exact keys and defaults:
  - `POREP_MARKET_VERSION=v2`
  - `POREP_MARKET_V1_BRANCH=v1`
  - `POREP_MARKET_V2_BRANCH=main`
  - `POREP_MARKET_REPO=https://github.com/fidlabs/porep-market.git`
  - `POREP_MARKET_DIR=` optional local checkout override, if implemented
- Do not conflate `POREP_MARKET_BRANCH` with both versions unless you keep it as an explicit override with documented precedence.

Phase 3: V1 Preservation

- Make V1 setup and scenarios run against PoRep Market branch `v1`.
- Preserve V1 variables: `CLIENT_CONTRACT`, old proposal tuple, `acceptDeal`, old `getDealProposal`, V1 compact state checks.
- Bring over any current unreleased verified scenario scripts and keep their assertions.

Phase 4: V2 Harness

- Use live V2 contract ABIs from PoRep Market branch `main`.
- Add V2 deploy extraction for `DataCapEvidenceAdapter`.
- Add V2 provider/offer setup:
  - register provider with V2 `registerProviderFor(uint64,address,uint256,address)`
  - allow payment token with `setPaymentToken`
  - create active offer with `createOffer`
  - verify selected offer with preview call if current contract exposes it
- Add V2 proposal smoke:
  - compute deterministic `manifestHash`
  - pass full `SharedTypes.DealRequest`
  - assert accepted state `20`
  - assert frozen provider/payment/capacity/data fields via split getters

Phase 5: V2 Deeper Tests To Implemented Boundary

- Add validator and prepared rail checks if current V2 FilecoinPay integration supports them.
- Add DataCapEvidenceAdapter allocation/evidence checks only for implemented functions.
- For missing V2 activation/payment/settlement behavior, create a blocked test scenario that exits non-zero only when the user explicitly asks for the unsupported full path, or a skipped test that documents the exact missing contract path. The goal is honest readiness, not green theater.

Phase 6: Docs and Final Verification

- Update docs to remove V1 assumptions from generic wording.
- Add runnable commands and expected outputs for both V1 and V2.
- Run all feasible verification gates.

### Verification Gates

Minimum local checks:

```bash
git status --short --branch
find scripts/porep-market -name '*.sh' -print0 | xargs -0 -n1 bash -n
just --list
```

Run any new script-test target you add, for example:

```bash
just porep-script-check
```

Run targeted V1 non-devnet smoke if available:

```bash
POREP_MARKET_VERSION=v1 bash scripts/porep-market/<final-v1-entrypoint> --help
```

Run targeted V2 non-devnet smoke if available:

```bash
POREP_MARKET_VERSION=v2 bash scripts/porep-market/<final-v2-entrypoint> --help
```

If a devnet is already running and the user has not forbidden longer checks, run the shallowest meaningful V2 devnet smoke:

```bash
just status
<final V2 deploy or proposal smoke command>
```

If devnet is not running or a check would require destructive reset, do not start/reset it silently. Report the exact command that remains unrun and why.

If you edit docs, verify relevant Markdown file paths exist and commands in docs match final file names.

If you add tests that rely on current PoRep Market V2 source, verify the specific ABI/function signatures from `/Users/mmach/git/1_neti/1_filecoin/2_porep_market` branch `main` during the same run.

### Progress Ledger

| Time | Work completed | Evidence | Remaining |
|---|---|---|---|
| 2026-07-01 09:39:48 CEST | Initialized execution from the goal pack; confirmed Boost is on `main`; confirmed sibling PoRep Market has `main` and `v1`; inventoried current script/docs anchors and grep hits showing current scripts are still V1-shaped. | `git status --short --branch` -> `## main`; `git -C ../2_porep_market branch --list main v1` -> `* main`, `+ v1`; `rg ... scripts/porep-market docs justfile` showed V1-only `CLIENT_CONTRACT`, old `proposeDeal`, `acceptDeal`, `getDealProposal`, and old `registerProviderFor` call sites. | Add failing script-harness tests, then migrate V1 and prepare V2 harness. |
| 2026-07-01 09:48:26 CEST | Added versioned layout and checks: V1 scripts copied under `scripts/porep-market/v1/`; shared helpers moved under `shared/`; V2 setup/deploy/provider/proposal smoke and full-path blocker added under `v2/`; README and ignored docs updated with V1/V2 routing; `justfile` gained versioned targets. | `just --list` lists `porep-v1-deploy`, `porep-v1-happy-path`, `porep-v2-deploy`, `porep-v2-proposal-smoke`, `porep-v2-full-happy-path`, `porep-script-check`; `just porep-script-check` passed; blocker check exited `2` as expected; `rg` against `../2_porep_market/src` confirms `proposeDeal(SharedTypes.DealRequest)`, split getters, `registerProviderFor`, evidence methods, and no `createOffer`/`setPaymentToken`. | Final audit still pending. Docker/devnet is down, so live V2 deploy/proposal smoke was not run. |
| 2026-07-01 09:50:00 CEST | Final static audit completed. | `git diff --check` passed; `just porep-script-check` passed; `just --list \| rg 'porep-(...)'` returned all versioned targets; `git status --short --branch` shows Boost on `main` with only this script/doc work visible. | Live Boost devnet V2 run remains the next verification step once Docker/devnet is up: `just porep-v2-deploy && just porep-v2-proposal-smoke`. |
| 2026-07-01 09:55:01 CEST | Strengthened V2 tests and prepared the deeper implemented boundary: proposal smoke now asserts frozen data/terms/capacity/payment/SLI fields, V2 ABI source test added, validator creation and prepared-rail smoke scripts added, versioned setup installs Node deps for `sign_permit.js`, and `porep-v2-deploy` deploys MockUSDC for rail setup. | `just porep-script-check` passed with `script_layout_test.sh`, `v2_abi_contract_test.sh`, and `bash -n`; `git diff --check` passed; `node --check` passed for V1 and V2 `sign_permit.js`; `just --list` includes `porep-v2-validator-rail-smoke`; `just status` still reports missing Docker socket and `devnet: down`. | Live Boost devnet V2 run remains blocked by Docker not running: `just porep-v2-deploy && just porep-v2-proposal-smoke && just porep-v2-validator-rail-smoke`. |
| 2026-07-01 09:57:47 CEST | Started Docker Desktop successfully and rechecked runtime state; Boost devnet containers are still not running. Made V2 provider setup idempotent by refreshing capabilities, available space, price, payee, and duration limits for an already-registered provider so reruns cannot inherit stale zero-price or capacity settings. | `open -a Docker` succeeded; `docker info` succeeded after one poll; `just status` returned `devnet: down`; `docker ps ... rg 'lotus|boost|yugabyte|devnet'` returned no running devnet containers; `just porep-script-check`, `git diff --check`, and `node --check` for both `sign_permit.js` files passed after the provider setup change. | Live Boost devnet V2 run remains pending because devnet is down and the goal pack says not to start/reset devnet silently. Required command when permitted/running: `just start` or equivalent, then `just porep-v2-deploy && just porep-v2-proposal-smoke && just porep-v2-validator-rail-smoke`. |
| 2026-07-01 11:19:56 CEST | User authorized local devnet cleanup; devnet was reset twice and brought up far enough for Lotus/miner/FEVM contract testing. Boost HTTP health stayed unhealthy because `boostd-data` failed Yugabyte migration `20230828111523_faddr.sql` with `pq: schema version mismatch ... expected 6, got 5`. V2 live gates were run against the usable Lotus/miner devnet with a clean throwaway V2 checkout override. | `just down` cleaned volumes; `docker exec lotus lotus chain head` succeeded; `docker exec lotus-miner lotus-miner info` succeeded; `just status` returned `devnet: ok`; Boost logs showed `Error: starting yugabyte store ... schema version mismatch`; `POREP_MARKET_DIR=/tmp/porep-market-v2-main-20260701111302 just porep-v2-deploy` passed and deployed `PoRepMarket`, `DataCapEvidenceAdapter`, `SPRegistry`, `ValidatorFactory`, `SLIOracle`, `SLIScorer`, and `MockUSDC`; `POREP_MARKET_DIR=/tmp/porep-market-v2-main-20260701111302 just porep-v2-proposal-smoke` passed for deal `1` in state `20`; `POREP_MARKET_DIR=/tmp/porep-market-v2-main-20260701111302 just porep-v2-validator-rail-smoke` passed for deal `2`, validator `0x21A65da4775D43453963d009fc994633fb89CCcD`, rail `1`. | Fix the default checkout collision found during live deploy and rerun final static gates. |
| 2026-07-01 11:19:56 CEST | Fixed the V2 default checkout collision by splitting empty `POREP_MARKET_DIR` into version-specific defaults: `scripts/porep-market/porep-market-v1` for V1 and `scripts/porep-market/porep-market-v2` for V2. Reran final verification gates and the intentional V2 full-path blocker. Added ignore coverage for versioned `v*/steps/node_modules/` created by `npm ci`. | `env -u POREP_MARKET_DIR POREP_MARKET_VERSION=v1 ...` printed `porep-market-v1`; the V2 variant printed `porep-market-v2`; `just porep-script-check` passed; `git diff --check` passed; `node --check` passed for V1 and V2 `sign_permit.js`; `just porep-v2-full-happy-path` exited `2` with the dummy `DataCapEvidenceAdapter` activation/status blocker; `git check-ignore -v scripts/porep-market/v2/steps/node_modules/.package-lock.json` matched `scripts/porep-market/.gitignore:11:v*/steps/node_modules/`; `docker compose ... ps` showed Lotus, miner, Yugabyte, and demo HTTP healthy with Boost unhealthy due the separate LID migration issue. | Final audit only; no requested code/test work remains. |

### Resume Rule

After any resume, interruption, or compaction, re-read this file and the progress ledger before continuing. Then run `git status --short --branch` in Boost before editing further. Do not rely on memory of earlier turns.

### Completion Rule

Do not mark the goal complete until every checklist item is complete or explicitly marked blocked with exact evidence, and every verification gate that can be run safely has current output. Budget exhaustion, elapsed time, partial migration, or “the plan is ready” is not completion.

### Final Response Shape

Return:

- files changed, grouped by V1 migration, V2 harness/tests, config, docs, and verification
- exact version/branch configuration keys and defaults
- V1 commands that remain runnable
- V2 commands/tests that were added
- verification commands run and result
- blocked V2 test areas with exact missing contract path/function evidence
- residual risk
