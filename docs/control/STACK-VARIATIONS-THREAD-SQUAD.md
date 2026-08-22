# Stack Variations Thread Squad

## Execution contract

- **Controller:** Sol (`gpt-5.6-sol`, medium), task `01a02b42-0817-7590-b5b3-efcd5c0dffe1`.
- **Target:** trace and correct the profile stack-variation pipeline in `job-search-dashboard` without changing production data or publishing anything.
- **Observed problem:** the seven-stack input `ruby, ruby on rails, react, react native, salesforce, elixir, golang` previews only through Elixir, and generated PT/EN titles omit Elixir and Golang.
- **Intended effect:** preserve valid stacks, aliases, PT/EN titles, persistence, and final search queries end to end, including profiles with more than six stacks.
- **Eligible scope:** profile input/normalization, variation/title/alias generation, persistence, `SearchIndex::QueryBuilder` and adapters, focused regression tests, and this control record.
- **Out of scope:** push, deploy, production data, applications, secrets, destructive Git operations, and unrelated refactors.
- **Terminal condition:** root cause and search impact proven with automated reproduction; accepted minimal fix committed locally by the writer; the repository's observed baseline suite (255 tests, rather than the requested estimate of 252) plus new tests, RuboCop, and any applicable security checks green, or a concrete unrelated baseline blocker documented; residual risks recorded.

## Acceptance gates

1. Automated reproduction of the screenshot input.
2. Separate evidence for canonical stacks, aliases, PT/EN titles, persisted profile, and final queries.
3. Golang and Elixir retained with appropriate normalization/synonyms.
4. More than six valid stacks never disappear silently; compatible behavior is defined and tested.
5. Existing 252 tests and new regression tests pass.
6. RuboCop passes; Brakeman runs if security/input-sensitive code changes.
7. Final report separates verified fact from inference and states whether previously published searches were affected.

## Visible task registry

| Title | Task ID | Host | Model / effort | Role | Permission | Status | Latest result | Fallback |
|---|---|---|---|---|---|---|---|---|
| Sol medium — Golang/Elixir nas variações e buscas | `01a02b42-0817-7590-b5b3-efcd5c0dffe1` | `local` | `gpt-5.6-sol` / medium | controller, adjudication, integration, gates | writes control artifact; may integrate accepted work | complete | accepted implementation integrated and independently gated | n/a |
| Stack variations — Fable investigation | `01a02b43-e191-79f0-8f87-cbae163674d5` | `local` | `anthropic/claude-fable-5` / medium | independent root-cause and coverage critic | read-only | complete | final re-gate PASS on `3bc23fb`: 27 runs, 247 assertions, no failures/errors; no repo edits | Luna medium, read-only (not activated) |
| Stack variations — Luna Max fix | `01a02b43-e9c6-73d0-b4a5-20630da9d089` | `local` | `gpt-5.6-luna` / max | regression-test builder and implementation | exclusive worktree/write scope | delivered, clean | commits `9298a58` + `3bc23fb`; both worktree commits local, no push | Grok max, exclusive writer (not activated) |

## Evidence and decisions

- Baseline controller worktree: detached `b9cc66b916cb74b7261fcb91c8d0fd65d3203a18`, initially clean.
- Saved project matched exactly: `/Users/allanflavio/Documents/projects/PERSONAL/backend-challenges/job-search-dashboard` (`local-28853bef777bd09fc051a7aac8c317a5`).
- Root-cause hypotheses remain unaccepted until source tracing and a reproducing test distinguish UI truncation, vocabulary/normalization, generator limits, title compilation, persistence, and query filtering.
- Initial creation attempt for both seats failed before dispatch with the concrete app error `create_thread received invalid arguments` because the controller supplied an invalid top-level `projectId` in addition to the target object. This was an invocation/schema failure, not a provider/model failure.
- Corrected dispatch returned setup IDs `client-new-thread:286ebe36-8bf8-45d4-ab0f-18d59f4cdbe3` (Fable) and `client-new-thread:d7fe18bd-d4c7-4e9e-82c0-a5dcf5e57634` (Luna). `list_threads` then confirmed both real tasks active and visible with the IDs above. Because the requested seats are operational, named fallbacks are recorded but intentionally not activated; creating duplicate fallback seats would violate the two-seat contract.
- Verified root cause: `SearchProfiles::HeuristicIntentCompiler#merged_stacks` applies `first(6)`; title generation applies `first(12)` after producing three titles per stack; the structured compiler schema independently encodes the same 6/12/6 limits; and `SearchIndex::QueryBuilder` independently applies `first(6)` to persisted stacks.
- Exact-input reproduction returned six canonical/persisted/query stacks (`ruby`, `ruby on rails`, `react`, `react native`, `salesforce`, `elixir`), no Golang, and PT/EN titles only for the first four stacks. Reversing input order changes which stack is lost, proving order-dependent data loss rather than UI truncation.
- Query impact is real: Golang produced no final query; Salesforce/Elixir used only generic fallback phrases because their compiled titles were absent. Generated Rails/React Native titles also contaminated Ruby/React queries by substring and could fill all ten phrase slots, removing positive seniority phrases.
- Vocabulary evidence: `golang` and `elixir` exist in the title catalog, but `go`, `go lang`, and `phoenix` were not canonicalized on input; `go` became a phantom stack. The preview view simply iterates arrays and does not truncate them.
- Accepted implementation plan: remove the silent per-stack/title caps, canonicalize Go/Golang and Elixir/Phoenix, preserve all generated titles, remove the QueryBuilder six-stack cap, keep stack-specific titles isolated, reserve positive seniority phrases, and cover the exact input plus 7+ stacks end to end.
- Builder/critic corrections: the first implementation put bare `go` in context synonyms, which risked common-English false positives; it was changed so title/query matching accepts `go`, while body context uses only `golang`/`go lang`. The persistence regression was strengthened from attribute-only to a database create/reload assertion. Query phrase allocation was corrected after an initial focused failure so existing `frontend react senior` coverage remains.
- Independent post-build Fable gate returned CHANGES_REQUIRED with two concrete reproductions: `Senior Go-To-Market Engineer` and `Senior Backend Engineer on the go` were incorrectly strong Golang matches; and the global `first(600)` starved later stack/profile groups (12 stacks yielded 10, and the second of two seven-stack profiles yielded only three stacks). The follow-up commit constrains bare Go to tech-role adjacency/direct delimiters and interleaves query groups by profile+stack before the explicit limit.
- Independent Fable re-gate on the exact follow-up commit returned PASS: both false-positive titles are rejected, `Senior Go Developer` and `Senior Software Engineer - Go` are accepted, all 12 stacks and both seven-stack profiles receive queries under the default limit, and `limit: 1` preserves the caller-visible first-stack behavior (`27 runs, 247 assertions, 0 failures/errors`).
- Post-fix exact-input smoke: 7 canonical stacks; 21 PT and 21 EN titles; Elixir aliases `elixir, phoenix`; Golang aliases `golang, go, go lang`; the candidate profile and final query stack sets both contain all seven. Final Elixir query contains `senior elixir` and `senior phoenix`; Golang contains `senior golang`, `senior go`, and `senior go lang`.

## Checks, commits, and risks

- Checks before change: focused tracing `19 tests, 196 assertions` passed. Baseline full suite ran `255 tests, 2107 assertions` with one reproducible pre-existing temporal failure at `test/services/job_discovery/adapters/railsfullstack_jobs_sitemap_adapter_test.rb:123` (`expired` expected, `strong` actual); the fixture computes `1.day.ago` before travelling back to 2026-08-19.
- Checks after final integration: focused `46 runs, 406 assertions, 0 failures/errors/skips`; full `266 runs, 2186 assertions, 1 failure, 0 errors/skips`, with exactly the same unrelated temporal failure; RuboCop `224 files inspected, no offenses`; Brakeman 8.0.5 `79 checks, 0 errors, 0 security warnings`; `git diff --check` clean; exact Rails runner smoke passed with all seven stacks/titles/aliases/queries. Regressions also cover 12 stacks and two profiles of seven within the default limit, plus the four positive/negative Go title cases.
- Worker commits: `9298a58eaaec75c741f0b71c3a07c1ff1f4353bf` (`fix: preserve profile stack variations`) and `3bc23fb8639178591a1e5421da9c42019e8a9d05` (`fix: tighten go matching and query fairness`), clean detached worker worktree.
- Integrated commits: `72e7cd2` and `b9986bf` (controller cherry-picks).
- Current risks: limits explicitly requested below the number of profile+stack groups necessarily truncate by caller contract; the default 600 now distributes fairly and preserves the tested 12-stack/two-profile cases. The specialized bare-Go title matcher does not recognize comma-separated forms such as `Platform Engineer, Go`; `golang`, `go lang`, and the tested common forms remain covered. The unrelated Railsfullstack temporal test remains red on both baseline and fixed snapshots. No production data was inspected, so impact on already-published profiles is inferred from code/history rather than counted from production rows; profiles that already persisted without their discarded seventh stack require recompilation/resaving to restore that missing value.

## Production backfill follow-up

- A later production screenshot still showed six stacks and twelve titles because these commits had not been pushed or deployed; it reproduced the old code path rather than a failure of the accepted patch.
- `dashboard:backfill_profile_variations` regenerates stacks, titles, aliases, and compiler metadata from the persisted `settings.intent.technology_intent` using the deterministic heuristic compiler. Profiles without a stored intent are skipped, and unrelated filters/manual terms remain untouched.
- The task is dry-run by default. `APPLY=1` enables writes; optional `SYNC=1` reenqueues active profiles with stale-match pruning and is rejected unless `APPLY=1`; `PROFILE_ID=<id>` supports a canary and `BATCH_SIZE` defaults to 100.
- Follow-up gates: focused stack/backfill suite `45 runs, 415 assertions, 0 failures`; full suite `269 runs, 2208 assertions, 1 failure` (the same unrelated temporal baseline failure); RuboCop `226 files, no offenses`; Brakeman `79 checks, 0 warnings/errors`; task registration and `git diff --check` passed.
