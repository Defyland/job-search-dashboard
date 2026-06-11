# Decision Journal

Running log of every technical decision: what was decided, why, which alternatives were
rejected, and the commit/refs. Newest entries first. One entry per decision.

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
