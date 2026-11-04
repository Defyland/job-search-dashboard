# Assisted daily discovery

Rails remains the canonical ingestion and matching engine. Its native daily
discovery is configured at 08:30 America/Sao_Paulo in `config/recurring.yml`.
The complementary agent searches public indexes and original career pages;
it is not limited to the fallback source catalog.

## Executor failure diagnosed on 2026-11-04

The former Codex automation was ACTIVE at 09:00, using GPT-6 Luna/high, but
its recorded execution policy was `workspace-write` with
`network_access=false`. Requests failed before HTTP with curl exit 6 and HTTP
000. Retrying DNS or increasing HTTP timeouts cannot fix a network-disabled
executor.

Reproduce the failure without a credential:

```sh
codex sandbox -c 'sandbox_mode="workspace-write"' \
  -c 'sandbox_workspace_write.network_access=false' -- \
  curl -sS --connect-timeout 5 --max-time 15 -o /dev/null \
  -w '%{http_code}' https://web-production-b2243.up.railway.app/up
```

Run the same curl command in the intended network-enabled executor. A health
response alone is insufficient: also confirm an authenticated GET to
`/api/v1/codex_fallback_sources` returns current `policy.profiles`, queries,
and the expected ingestion endpoint. Never print the bearer credential.

The corrective execution target is the existing T3 thread with network
access, GPT-6 Luna, reasoning `high`, and service tier `priority` (Fast),
scheduled daily at 08:00 America/Sao_Paulo. Pause the old Codex automation
after the replacement is saved; do not leave both daily schedules enabled.
Do not change global sandbox settings or Railway infrastructure for this fix.

## Run contract

1. Read current policy before searching or posting. Use the existing
   `INGEST_SHARED_TOKEN` or ignored `tmp/.ingest_shared_token`. Fail closed
   if authentication, networking, or the policy contract fails. Do not fall
   back to historical profiles. Use separate connection/read timeouts,
   allowing up to 95 seconds for the policy response and at most one retry
   for a transient GET failure; never retry 401/403 blindly.
2. Group equivalent profiles for research, while preserving every profile
   for backend classification. Prioritize Ruby/Rails, React, and React Native;
   retain coverage of other active profiles. Rotate public sources and record
   coverage by profile and stack, rather than executing the first queries
   repeatedly. The returned query list is guidance, not a requirement to
   execute all 600 queries daily.
3. Search the web for complementary vacancies. Prefer the last 24 hours;
   record unknown recency honestly. Open the original vacancy, confirm it is
   active and directly apply-able, and check remote/geographic eligibility,
   seniority, language, and exclusions against all current profiles.
4. Deduplicate candidate URLs before ingestion. Preserve original source
   identity. Only mark a source as checked after actual access; inaccessible
   pages are coverage gaps. Do not bypass access challenges or create paid
   services or credentials to improve coverage.
5. POST verified candidates using `trigger_source=codex_automation`,
   `window_label=24h`, and `discovery_method=luna_web_search`. Rails owns
   deduplication and final classification. Record the returned `search_run_id`
   and counters. A POST timeout is ambiguous: do not resend unless persistence
   can be checked safely. Job deduplication does not make run creation
   idempotent.
6. Save timestamped evidence under `tmp/codex-job-search-runs/`: current
   policy, queries, pages, candidates, actual checked source slugs, payload,
   receipt, and coverage gaps. No credentials, authorization headers, or
   signed URLs. Report blocked, partial, or completed with real counters;
   unavailable data is not zero jobs. Do not post an empty success when all
   searches were blocked.

## Acceptance and boundaries

- The old sandbox configuration reproduces the failure and the corrected
  executor reaches both health and the authenticated policy endpoint.
- Exactly one complementary daily schedule is enabled, at 08:00 local time,
  with the intended thread/model settings confirmed by readback.
- Scheduled end-to-end discovery is only verified after a scheduled run
  produces research evidence and an ingestion receipt. Scheduler acceptance
  and a health check do not prove vacancy ingestion or the native worker.
- The T3 server and machine must be running and connected at execution time.
  Follow the scheduler's reported next run time; do not claim hosted execution.
- No changes to profiles, sources, native cron, matching, infrastructure, or
  automatic job applications are part of this correction.

## Refined contract (implemented locally, not deployed)

Status as of 2026-11-04:

- Implemented locally in the working tree. **Not deployed.**
- The production backend is still the previous build. Until it is deployed, its
  responses carry no `coverage` block, no `replayed` flag, and no client-run
  idempotency. Treat those absences as legacy behaviour.
- The complementary agent schedule at 08:00 America/Sao_Paulo is reported
  active. The native Rails worker stays at 08:30 BRT (11:30 UTC) in
  `config/recurring.yml`; this change does not touch it.
- Model and cadence are set outside the prompt, after final approval.
- Nothing here proves that production cron, the new UI, or production ingestion
  works. Scheduled end-to-end discovery is verified only by a scheduled run that
  produces research evidence and an ingestion receipt.

This section documents the contract as implemented, lists explicit differences
from the Run contract above, and points to the literal prompt in
[discovery-agent-prompt.md](discovery-agent-prompt.md). The text above is not
edited. Where this section differs from it, this section governs.

### 1. Query builder (`JobDiscovery::SearchIndex::QueryBuilder`)

- Identical query strings are emitted once. The legacy `search_profile_id`
  keeps the first profile; `search_profile_ids` lists all associated profiles.
- Queries are grouped by stack, title phrases, remote group and negative terms.
  Each group keeps a queue of hosts. The queues are strided and interleaved
  round-robin.
- The daily window is a rotation: `start = (days since 2026-01-01 * limit) mod N`,
  then `rotate(start).first(limit)`. The population does not depend on the date;
  only the window does.
- For a stable rectangular population, `query_builder_test.rb` asserts that
  group counts differ by at most 1. Host
  counts differ by at most 1 when `gcd(groups, hosts) == 1`, and by at most 2
  otherwise. No query repeats within a rectangular shape. Coverage of the full
  list within any run of consecutive days is asserted by the test "rotation
  covers every query within any run of consecutive days". By construction that
  run has `ceil(N / B)` days, where `B` is the budget. With heterogeneous host
  eligibility, only coverage and determinism are guaranteed; balance is best
  effort. These cycle guarantees require the query population to stay stable.
- Not guaranteed: fairness across profiles. The builder does not weight
  priority. The Rails/React/React Native priority exists only in the agent
  prompt.

### 2. Board seeder (`JobDiscovery::SearchIndex::BoardSeeder`)

- Queries are bounded by `max_queries` (`SEARCH_INDEX_MAX_QUERIES`, default 60).
  Results per query are bounded by `results_per_query` (default 10).
- Each per-query summary entry carries `host`, `source_slug`, `target_stack`,
  `search_profile_ids`, `result_count`, `discovered_seed_count`, and, when that
  query raised, `error` with the error class name only. Query text is omitted.
- `discovered_seed_count` counts values absent from a snapshot taken at load and
  first seen in this run.
- `seeded_count` is what was actually persisted under a row lock. Under
  concurrency another writer can persist the same value first, so the sum of
  `discovered_seed_count` may exceed `seeded_count`.
- The top-level `errors` array holds `"host: message"` strings, which can contain
  provider text. Review them before copying anything into evidence.

### 3. Cron recovery (`JobDiscovery::Orchestrator`)

- Applies only when `trigger_source` is `cron` and the source has a non-nil
  `last_full_scan_at`.
- Effective window per source: `min(7, max(requested, ceil(days since
  last_full_scan_at)))`.
- With a nil `last_full_scan_at`, the requested window is used.
- Manual and `codex_automation` runs always use the requested window.
- `last_full_scan_at` advances only when that source's scan succeeds. A scan
  that raises leaves it unchanged.
- The effective window is not recorded. `search_runs.window_label` and the run
  summary `window_days` keep the requested value.
- Caveat: a nil or non-positive `window_days` passed to the orchestrator is
  coerced to 20. It is not treated as "no window".

### 4. Coverage in the policy API (`GET /api/v1/codex_fallback_sources`)

- `coverage.native_sources[]` has `slug`, `host`, `last_full_scan_at` and
  `known_boards`.
- `known_boards` is an allowlist. Only the setting keys that
  `QueryBuilder::TARGETS` maps to that slug are exposed. Values are trimmed,
  deduplicated and sorted. Empty keys are omitted. Other settings are not
  exposed.
- `coverage.last_successful_codex_run` has exactly five fields: `id`, `status`,
  `started_at`, `finished_at` and `window_label`. It is the most recent
  `codex_automation` run with status `succeeded` or `partial`. Runs with trigger
  `manual` or `cron`, and runs with status `failed` or `running`, are ignored.
  The raw `summary` is never exposed.
- A timestamp alone is not coverage proof. A full-coverage claim needs the run's
  own evidence, not this field.
- Skipping: a single board may be skipped only with recent verification
  evidence for that board. Its presence in `known_boards` does not prove a recent
  check. Whole ATSs are never skipped.
- Caveat: `final_status` is `partial` only when at least one job was imported or
  updated and at least one was rejected. A run in which every candidate was
  rejected finishes `succeeded`. It can therefore become
  `last_successful_codex_run` without accepting any vacancy.

### 5. Market (`JobMarketClassifier`, persisted as `jobs.market`)

- Values: `national`, `international`, `unknown`.
- Precedence, first match wins: empty input gives `unknown`. A restricted Brazil
  phrase gives `national` ("anywhere in brazil", "todo o brasil", "qualquer
  lugar do brasil"). A global or regional phrase gives `international`. Brazil
  together with a foreign country gives `international`. Brazil alone gives
  `national`. A foreign country alone gives `international`. Anything else gives
  `unknown`.
- Company nationality is not an input. A foreign company with a Brazil-only
  posting is `national`.
- Inputs are only `location_text` and `remote_text`, passed from
  `Job#normalize_fields`. Title, description, company and raw payload never reach
  the classifier.
- Dictionaries are explicit and limited. "US only" matches no phrase, so it is
  `unknown` for market. "United States" and "USA" are foreign phrases, so a
  posting that mentions them alone is `international`.
- `unknown` is not a selectable filter. The "Todas" tab shows the count notice
  "N sem mercado identificado" for unknown rows.
- Market is display only. Geographic eligibility is a separate check in
  `JobDiscovery::Policy`, which rejects explicit regional restrictions such as
  "US only" (see README, "Geographic eligibility").
- The rules are frozen as a copy in
  `db/migrate/20261104150000_add_market_to_jobs.rb`. Later edits to the
  classifier do not change that migration's backfill.

### 6. Ingestion idempotency (`POST /api/v1/job_ingestions`)

- `run.client_run_id` is optional. When present, it must be a string and is
  unique across `search_runs`, by a partial unique index.
- The stored `request_digest` is the SHA-256 of the canonical parsed params:
  object keys sorted recursively, array order preserved.
- `201` with `replayed: false`: a new run was created with this key.
- `200` with `replayed: true`: same key and same canonical digest. The original
  counters are returned and no new run is created.
- `409` with `error: client_run_id_conflict`: same key, different digest. The
  body is not changed under that key.
- A keyed run that fails validation rolls back, so the key is released. A keyless
  run stores no key and gets no idempotency.
- Retry rule: a retry re-sends the exact same body, endpoint and
  `Content-Type: application/json`.
- Presence of `coverage` in the GET response does not prove idempotency.
- Caveat: until the new backend is deployed, a `201` without `replayed` is a
  legacy success receipt. It has no run-level idempotency and must never be
  re-sent.

Example `run` object for the new contract (illustrative values):

```json
{
  "run": {
    "client_run_id": "codex-20261104T110000Z-batch1",
    "started_at": "2026-11-04T08:00:00-03:00",
    "window_label": "24h",
    "window_start": "2026-11-03T08:00:00-03:00",
    "trigger_source": "codex_automation",
    "discovery_method": "luna_web_search",
    "queries_executed": 30,
    "hosts_checked": 12,
    "source_slugs": ["example-source-slug"],
    "gaps": ["react native: no verified candidate in window"],
    "budget": 30
  },
  "strong_matches": [],
  "borderline_matches": [],
  "rejections": []
}
```

### 7. Agent run metadata (`run`)

Fixed fields for the new contract:

- `client_run_id` (string): stable for the batch. Generated once and reused for
  any identical retry.
- `started_at` and `window_start` (ISO 8601 with offset).
- `window_label`: `"24h"`, or `"Nd"` when the coverage-based recovery window
  applies.
- `trigger_source`: `codex_automation`.
- `discovery_method`: `luna_web_search`.
- `queries_executed` (integer).
- `hosts_checked` (integer): unique hosts actually opened.
- `source_slugs` (array of strings): only sources actually verified.
- `gaps` (array of strings).
- `budget` (integer): the bound actually used.

Never send checked-at facts the agent did not observe. Extra run keys are stored
in the run summary and do not break ingestion. The backend reads only the keys it
knows.

### 8. Differences from the Run contract above

- Step 1 (policy). Adds the 95-second read timeout, one transient GET retry, and
  the rule that a blocked GET ends in NOT VERIFIED rather than zero jobs. The
  earlier text said only "fail closed".
- Step 2 (queries). Adds a 30 initial and 60 maximum budget, `run.budget`, and
  deduplication and rotation before selection. The earlier "rotate public
  sources" is kept.
- Step 3 ("prefer the last 24 hours"). For coverage-backed runs, replaced by the
  recovery window of 1 to 7 days (step 6 of
  [discovery-agent-prompt.md](discovery-agent-prompt.md)). 24 hours remains the
  default when coverage is absent.
- Step 4 ("only mark a source as checked after actual access"). The agent rule is
  kept. The server behaves differently: on every successful `codex_automation`
  ingestion, Rails sets `last_codex_checked_at` on each codex-fallback source
  named in `run.source_slug(s)` and in the job or rejection `source_slug` values. That is a
  bookkeeping claim, not coverage proof. A failed run marks nothing. The agent
  must list only verified slugs in `source_slugs`.
- Step 5 ("`window_label=24h`"). Now `"24h"` or `"Nd"` by recovery window. The
  label is stored as sent. Section 3's effective cron window is not part of it.
- Step 5 (POST timeout: "do not resend unless persistence can be checked
  safely"). Tightened. A timeout or network loss after the request was sent stops
  the run with status PENDENTE. There is no automatic retry, even with the new
  contract. The API offers no safe persistence check, so that path is closed.
- Step 5 (record `search_run_id`). Now distinguishes the legacy `201`, `201` with
  `replayed: false`, `200` with `replayed: true`, and `409`.
- Step 6 (evidence root `tmp/codex-job-search-runs/`). Now
  `/tmp/codex-job-search-runs/<run_id>/`, with the same rule against saving
  credentials or signed URLs.
- Step 6 (report). Earlier statuses "blocked, partial, completed" are replaced in
  the prompt by FEITO / PENDENTE / NÃO VERIFICADO, with real counters.
- `known_boards` (not in the earlier contract). It guides exploration of new
  companies. Skipping is per board and needs recent verification evidence.
- Priority (the Run contract's step 2). Kept as an agent instruction. The builder
  does not enforce it (section 1).

### 9. Evidence and validation

- Evidence root for each run: `/tmp/codex-job-search-runs/<run_id>/`, with a UTC
  run id.
- Market classifier evidence (local, not versioned):
  `/tmp/pair-discovery-markets/backend/RESULT.md`. It covers only the classifier
  and migration. It does not cover the query builder, seeder, cron recovery or
  API. Those sections rest on the test files named below, which were not re-run
  for this documentation change.
- Test files that back sections 1 to 7:
  `test/services/job_discovery/search_index/query_builder_test.rb`,
  `test/services/job_discovery/search_index/board_seeder_test.rb`,
  `test/services/job_ingestions/importer_test.rb`,
  `test/services/job_market_classifier_test.rb`,
  `test/controllers/api/v1/job_ingestions_controller_test.rb` and
  `test/controllers/api/v1/codex_fallback_sources_controller_test.rb`.
- This change is documentation only. It changes no code, tests, fixtures, schema
  or migrations.

### 2026-11-04 — final POST ambiguity guard

A 5xx response, a response without a JSON body, or any unlisted status ends
the scheduled run as PENDENTE. Record the status and do not resend. Retries
are manual only, never within the scheduled execution, and must keep the
exact body, endpoint and Content-Type. This also applies to the legacy backend.
