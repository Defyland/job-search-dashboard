# Decision Journal

Running log of every technical decision: what was decided, why, which alternatives were
rejected, and the commit/refs. Newest entries first. One entry per decision.

---

## 2026-06-29 - Publish canonical architecture and case-study docs for the current product surface

**Decision:** Added `docs/architecture.md` and `docs/engineering-case-study.md`, linked them from the
README, and documented the current public/product surface as "public Farol landing plus real waitlist
capture, private operator dashboard, Rails-native discovery, Codex fallback by contract" instead of
leaving that story spread across the README, tests, and older historical notes.

**Why:** The repo already had strong operational detail, but not in the canonical file names that human
reviewers and AI readiness tooling expect. The absence of dedicated architecture/case-study docs made the
technical story harder to validate in under five minutes, and older notes no longer described the current
landing surface precisely.

**Rejected:** A broader doc rewrite or code churn. The code already proves the boundaries through
`JobDiscovery::Orchestrator`, `JobIngestions::Recorder`, `SearchRunsController`, `SourcesController`, and
the waitlist flow. The right change here is packaging and truthfulness, not new abstractions.

**Verification:** reran full Rails tests, RuboCop, Brakeman, and the local AI-readiness eval after adding
the docs and README fast path.

**Refs:** `README.md`, `docs/architecture.md`, `docs/engineering-case-study.md`.

---

## 2026-06-12 — Split JobDiscovery::Policy by responsibility, not by pattern

**Decision:** Kept `JobDiscovery::Policy` as the public entrypoint, but moved its two internal
responsibilities into focused collaborators under the same namespace:
`JobDiscovery::Policy::CriteriaBuilder` compiles one profile into regex criteria, and
`JobDiscovery::Policy::CriteriaEvaluator` classifies one candidate against that compiled profile.
`Policy` now just selects profiles, builds evaluators and returns the best accepted decision.

**Why:** The old `policy.rb` mixed catalog/vocabulary, criteria compilation and runtime classification in
one 437-line file. That made the core matching rule hard to scan and expensive to change safely. This cut
keeps one stable API for callers (`potential_match?`, `classify`, `contract`, `default_profile`) while
separating compile-time concerns from runtime decision logic.

**Rejected:** a broader "clean architecture" rewrite with commands/use-cases/entities around matching.
That would add indirection without changing ownership. The useful cut here is just two collaborators with
one reason to change each, inside the same bounded namespace.

**Verification:** existing `JobDiscovery::PolicyTest`, `BootstrapperTest`, `ImporterTest` and `SyncTest`
rerun green; full suite, RuboCop and Brakeman rerun after the extraction.

**Refs:** `app/services/job_discovery/policy.rb`,
`app/services/job_discovery/policy/criteria_builder.rb`,
`app/services/job_discovery/policy/criteria_evaluator.rb`.

---

## 2026-06-12 — Canonicalize JobMatch writes behind one upserter

**Decision:** `JobMatch` creation/update/recovery now has one write path in
`JobMatches::Upserter`. Both `JobIngestions::Store#persist_job_matches` and
`SearchProfiles::Bootstrapper#upsert_match` delegate to it instead of carrying duplicate
`find_or_initialize_by + transaction + rescue RecordNotUnique/RecordInvalid` flows.

**Why:** This is a critical persistence boundary. The old shape had the same uniqueness-race handling
and attribute mapping duplicated in two workflows: Codex/adapter ingestion and profile cache backfill.
That makes future changes to `raw_decision`, timestamps, `user_state`, or eligibility flags easier to
drift. One owner is the practical clean-architecture cut here; adding callbacks or concerns would hide
the write semantics instead of clarifying them.

**Rejected:** moving this into `JobMatch` callbacks/class methods. The rule depends on a policy decision
plus workflow timestamp and is shared by orchestration services, so a small dedicated writer is the
clearest owner.

**Verification:** added `JobMatches::UpserterTest` for create/update semantics; full suite, RuboCop and
Brakeman rerun after the refactor.

**Refs:** `app/services/job_matches/upserter.rb`, `app/services/job_ingestions/store.rb`,
`app/services/search_profiles/bootstrapper.rb`, `test/services/job_matches/upserter_test.rb`.

---

## 2026-06-10 — Make the Farol landing data-driven and drop the placeholder waitlist

**Decision:** The landing now reflects the real product instead of marketing placeholders.
`PagesController#home` exposes `@source_count`/`@source_names` from `JobSources::Catalog.defaults` (21
sources); the hero trust line shows "21 fontes mapeadas" and the marquee is server-rendered from the real
catalog names. The discovery cadence copy was corrected to "Todo dia às 08:30 BRT" to match the actual
`daily_discovery_run` (config/recurring.yml, 11:30 UTC) — dropping the aspirational "de hora em hora" and
"25+ fontes". The non-functional email waitlist (`form#capform`) was removed; every CTA now routes to the
operator login (`new_session_path`).

**Why:** The page should not claim cadence or counts the product does not deliver, and a waitlist form
that posts nowhere is worse than no form. Sourcing the numbers from the catalog keeps the copy honest as
the catalog grows.

**Verification:** `PagesControllerTest` asserts the live count string, the daily-cadence copy, the absence
of the old claims, and that no `#capform` exists; full suite 154 runs / 711 assertions green on Ruby 3.4.9.

**Refs:** `app/controllers/pages_controller.rb`, `app/views/pages/home.html.erb`,
`test/controllers/pages_controller_test.rb`.

---

## 2026-06-10 — Farol landing becomes the root homepage with header login

**Decision:** Moved the Farol landing from the static `public/farol.html` into a Rails view at
`app/views/pages/home.html.erb`, served at `/` by a new `PagesController#home` (`root "pages#home"`).
The page is public (`allow_unauthenticated_access`); authenticated operators are redirected straight to
the radar (`jobs_path`). The header CTA is now a real login link (`Entrar` → `new_session_path`).

**Why:** `/farol.html` is not a homepage. The front door should be the landing for visitors and the radar
for operators, with one clear way in. Rendering through a controller (instead of a static
`public/index.html`) keeps the login redirect test-correct and lets `/` stay auth-aware without shadowing
the Rails router.

**Compatibility:** `after_authentication_url` is unchanged (still `root_url`), so login still redirects to
`/`, which now bounces authenticated users to `/jobs`. The existing `SessionsControllerTest`
(`assert_redirected_to root_path`) stays green; new `PagesControllerTest` locks both branches.

**Refs:** `app/views/pages/home.html.erb`, `app/controllers/pages_controller.rb`, `config/routes.rb`,
`test/controllers/pages_controller_test.rb`.

---

## 2026-06-10 — Product identity "Farol" + public landing page

**Decision:** Named the product **Farol** (PT: lighthouse/beacon) and shipped a standalone marketing
landing page at `public/farol.html`, served by Rails at `/farol.html`. Identity: ink-navy base with an
amber "beam" as the primary accent and a green "strong match" signal; type pairing Fraunces (display) +
Hanken Grotesk (body) + JetBrains Mono (data/dev accents); voice built on the lighthouse metaphor
(*varre / acende*). Copy is PT-BR for the BR/LatAm dev audience.

**Why:** The internal "Codex + Rails" framing is plumbing, not a product. "Farol" turns the app's own
"radar" language into one promise — a beam that sweeps the boards and lights up only on roles that match
your profile.

**Placement:** Static file under `public/` (like the existing error pages), NOT a Rails route — keeps the
authenticated dashboard at `/` untouched and adds zero runtime/dependency surface. CSP is disabled (Rails
default), so the Google Fonts CDN loads fine.

**Refs:** `public/farol.html`.

---

## 2026-06-10 — Harden the discovery Fetcher (retry, backoff, jitter, throttling)

**Decision:** Rewrote `JobDiscovery::Fetcher` to be resilient: per-host throttling with jitter,
retry with exponential backoff on transient network errors and HTTP 408/425/429/5xx, and honoring
`Retry-After`. Every knob is ENV-tunable (`SEARCH_MIN_REQUEST_INTERVAL`, `SEARCH_MAX_RETRIES`,
`SEARCH_BACKOFF_BASE`, `SEARCH_MAX_BACKOFF`, `SEARCH_REQUEST_JITTER`, timeouts). Delays funnel through
an injectable sleeper/clock/rng so the logic is unit-tested without real sleeps or network.

**Why:** Step 2 of the roadmap and the prerequisite to raising discovery frequency. The old Fetcher
failed the entire source scan on the first transient blip and hit hosts back-to-back; throttle +
backoff make scans fault-tolerant and polite, which lowers block risk.

**Public interface unchanged:** `call(url, limit:, headers:)` still returns the body and raises on
permanent failure, so every adapter is untouched. Dispatch now keys on the integer status range
instead of `Net::HTTP*` classes (for testability), behavior-equivalent for 2xx / 3xx / else.

**Deferred — conditional caching (ETag / If-Modified-Since):** intentionally NOT included. It reduces
bandwidth, not request *rate*, so it does little for the block-risk goal, and a durable per-URL cache
would need a schema change. Revisit as its own change if bandwidth/latency becomes the bottleneck.

**Verification:** new `test/services/job_discovery/fetcher_test.rb` (7 cases); full suite 152 runs /
692 assertions green on Ruby 3.4.9; RuboCop clean.

**Refs:** `app/services/job_discovery/fetcher.rb`, `test/services/job_discovery/fetcher_test.rb`.

---

## 2026-06-10 — Roadmap priority: notifications → Fetcher resilience → match quality → frequency

**Decision:** Improvement order is (1) push/email notifications on new strong matches,
(2) `JobDiscovery::Fetcher` resilience (backoff, jitter, conditional caching via ETag/If-Modified-Since),
(3) matching quality (`Policy`), (4) only then higher discovery frequency.

**Why:** Value is gated by external sources, not internal compute. `Fetcher`
(`app/services/job_discovery/fetcher.rb`) has no throttle/backoff/jitter/cache and uses an
identifiable bot UA, and sources already block automated clients (APInfo rate-limit, RubyOnRemote
Cloudflare challenge). Raising the cron alone multiplies block risk. Notifications cut
time-to-awareness even at the same cadence (today's model is pull-only).

**Rejected:** Just increasing `daily_discovery_run` frequency first. Deferred until Fetcher
resilience exists; then split cadence per source type (API sources hourly, fragile HTML scrapers daily).

**Refs:** advisory only, no code yet.

---

## 2026-06-10 — Deferred the behavior-changing P2/P3 refactors

**Decision:** Did NOT ship Policy decomposition, the double-classification redesign, or the
ingestion payload cap in this batch. Dropped the `normalize_list`/`freshness_at` consolidation entirely.

**Why:** Shipped straight to `main` (auto-deploys prod), so anything touching core matching/ingestion
behavior was too risky without characterization tests. `SearchProfiles::Vocabulary.normalize_list`
splits on `,`/`;`/newline, so it is NOT equivalent to the models' inline `normalize_list` — consolidating
would have been a silent regression.

**Refs:** to be done later on a dedicated branch/PR with characterization tests.

---

## 2026-06-10 — Centralized canonical job identity in `Job.find_duplicate`

**Decision:** Added `Job.find_duplicate(fingerprint:, canonical_url:)` as the single identity rule
(fingerprint first, canonical_url fallback); `JobIngestions::Store#find_existing_job` now delegates to it.

**Why:** The same `find_by(fingerprint) || find_by(canonical_url)` pattern was duplicated across the
store and the orchestrator linker. One owner keeps the dedupe rule from drifting.

**Refs:** commit `dc32f53` — `app/models/job.rb`, `app/services/job_ingestions/store.rb`.

---

## 2026-06-10 — Batched `DiscoveredJob → Job` linking to remove an N+1

**Decision:** Rewrote `Orchestrator#link_discovered_jobs!` to resolve all candidates in two queries
(`WHERE fingerprint IN (...) OR canonical_url IN (...)`, indexed in memory) instead of two `find_by`
per row. Added an orchestrator test asserting the accepted candidate is linked and the rejected one is not.

**Why:** Per-row queries were O(N) per scan. The batch version preserves the exact fingerprint-first,
canonical-fallback rule and is behavior-preserving (verified by tests).

**Refs:** commit `dc32f53` — `app/services/job_discovery/orchestrator.rb`,
`test/services/job_discovery/orchestrator_test.rb`.

---

## 2026-06-10 — Enforce SSL in production (Railway-safe)

**Decision:** Enabled `config.assume_ssl = true` and `config.force_ssl = true` in
`config/environments/production.rb`, with `config.ssl_options` excluding `/up` from the HTTP→HTTPS redirect.

**Why:** The app is session-cookie authenticated and public on Railway. Without this the session cookie
was not `secure` and there was no HSTS. `assume_ssl` trusts Railway's `X-Forwarded-Proto` so `force_ssl`
does not redirect-loop; excluding `/up` stops the platform healthcheck (internal HTTP) from being 301'd.

**Verification:** production env boots with `force_ssl=true`/`assume_ssl=true`; `/up` confirmed excluded
from redirect, real paths forced to HTTPS; deploy healthcheck passed.

**Behavior change in prod:** HTTPS is now mandatory — any plain-HTTP caller gets a 301 + HSTS.

**Refs:** commit `dc32f53` — `config/environments/production.rb`.

---

## 2026-06-10 — Bump Ruby 3.4.2 → 3.4.9 (not 3.5)

**Decision:** Bumped Ruby to 3.4.9 across `.ruby-version`, `.tool-versions`, and the Dockerfile
`ARG RUBY_VERSION`, kept in sync.

**Why:** Newest patch within the same 3.4 minor — ABI-compatible native gems, low risk, and the only
newer Ruby installed locally so the full suite could be verified before shipping.

**Rejected:** Ruby 3.5 — cannot be verified locally, larger jump, higher Rails 8.1 / native-ext risk.

**Verification:** `bundle install` recompiled native exts on 3.4.9; 145 tests / 671 assertions, RuboCop,
Brakeman, bundler-audit all green; CI (incl. system tests) green on 3.4.9.

**Refs:** commit `dc32f53` — `.ruby-version`, `.tool-versions`, `Dockerfile`.
