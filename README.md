# Job Search Dashboard

Rails 8 dashboard for configurable developer job discovery profiles. The default seeded profile still targets senior Ruby, Ruby on Rails, React, and React Native remote roles, but the product model now lets each user define stacks, title terms, seniority, location requirements, and eligibility preferences such as whether women-only affirmative roles should be included. The app accepts curated Codex ingestion, but Rails owns deterministic backfills, recurring scans, canonical job persistence, and profile-scoped matching.

## Architecture

The production flows are:

- `Rails recurring/manual discovery -> source adapters -> discovered candidates -> Rails persistence and dedupe -> private dashboard`
- `Codex fallback automation -> GET /api/v1/codex_fallback_sources -> assisted discovery for blocked sources -> POST /api/v1/job_ingestions -> Rails persistence and dedupe -> private dashboard`

What Rails owns:

- public Farol landing, persisted waitlist capture, and private authenticated UI
- canonical `Job`, `JobSource`, `SearchRun`, `SearchRunItem`, `SourceScan`, and `DiscoveredJob` records
- configurable `SearchProfile` records and per-profile `JobMatch` records
- dedupe by canonical URL and fingerprint
- user workflow state per profile: `new_match`, `seen`, `applied`, `ignored`
- job lifecycle state: `active`, `expired`
- run history and raw payload traceability
- deterministic source coverage for the adapters already implemented
- policy enforcement from each active profile: title-first seniority matching, stack matching, remote compatibility, negative terms, and women-only eligibility
- backend reclassification of every ingested job, including Codex fallback payloads
- configurable per-source search queries for public indexes that require term-driven scans, such as `Sólides`

What Codex owns:

- fallback discovery for sources explicitly marked with `codex_fallback_enabled`
- assisted search/navigation for sources that are blocked, rate-limited, protected by challenge pages, or too unstable for a native worker adapter
- validation that the job is still active and directly apply-able before posting it back to Rails; final match decisions still belong to Rails profile policies
- optional complementary discovery of new boards that can later become native Rails adapters

What Rails currently discovers by itself:

- `Gupy` company boards already known to the dashboard
- `Sólides` via the public `portal-vacancies-new/` API plus direct vacancy-page validation on `vagas.solides.com.br`
- `Recrutei` vacancy pages already known to the dashboard, plus optional company labels or direct vacancy URLs configured in `JobSource.settings`
- `Inhire` career pages discovered from persisted `*.inhire.app/vagas/<jobId>` URLs plus public tenant resolution
- `Lever` company boards discovered from persisted `jobs.lever.co/<company>/<posting>` URLs
- `Blue Coding` through the Lever postings API with its configured `bluecoding` company board
- `Greenhouse` boards discovered from persisted `job-boards.greenhouse.io/<board>/jobs/<id>` URLs
- `Ashby` job boards discovered from persisted `jobs.ashbyhq.com/<board>/<posting>` URLs
- `Teamtailor` company boards discovered from persisted `*.teamtailor.com/jobs/<id>` URLs or explicit `board_urls`
- `Prometeo Talent` through its Teamtailor-hosted board and public job details
- `SmartRecruiters` companies discovered from persisted `jobs.smartrecruiters.com/<company>/<posting>` URLs or explicit `company_identifiers`
- `Trampos` via public `api/v2/opportunities` pagination plus canonical opportunity detail pages
- `Coodesh` via the public jobs sitemap plus SSR job detail pages on `coodesh.com/jobs/*`
- `ProgramaThor` remote senior listing pages
- `Remotar` via public jobs API, incluindo links externos para ATSs como `Gupy` e `Inhire`
- `Workable` via public global jobs API
- `RemoteOK` via the public global jobs API
- `RemoteYeah` via its public RSS feed, plus configured job-page seeds
- `RailsFullstack` via its SSR remote collection, with sitemap/`JobPosting` fallback
- `Remotive` via the public remote jobs API
- `Himalayas` via the public jobs API
- `GoGloby` via its dedicated jobs sitemap and SSR vacancy pages
- public `Notion` job pages via Notion's own public page API
- `Artificial Intelligence Jobs` via its documented public jobs API
- `We Work Remotely` via its public category RSS feeds
- `beBee` via its public BR job search pages (profile-driven queries and remote
  filter configured in the source settings)
- the official `Rails Job Board` through its public RSS feed
- `Loxo` through public SSR career boards, initially seeded with FitNext
- `Luflox` through its public Firestore positions feed

The rest of the catalog is still present for normalization/filtering. Sources that are not practical for a native Rails adapter can be marked as Codex fallback sources; today that covers `APInfo` because its public search rate-limits automated clients, `Indeed` because its public search and job pages return a Cloudflare challenge to the Rails worker client profile, and `RubyOnRemote` because its public pages return a Cloudflare challenge to the Rails worker client profile. The stack-specific fallback catalog covers active ecosystem boards for Python/Django, JavaScript/TypeScript, React, Vue, Angular, PHP/Laravel/Symfony, Elixir/Phoenix, Go, Rust, Kotlin/Android, Swift/iOS, and C/C++/embedded roles. It includes official/community sources such as `Python Job Board`, `Django Community Jobs`, `Symfony Jobs`, plus focused boards such as `JavaScript Jobs`, `React Jobs`, `VueJobs`, `Angular.work`, `LaraJobs`, `Elixir Jobs`, `GolangProjects`, `RustJobs.dev`, `Kotlin Brasil`, `Mobile Career Swift`, `C++ Jobs`, and `EmbeddedJobs`. Profile search queries are only sent to ecosystem boards whose configured stack affinity matches the profile.

Portugal coverage is intentionally broad in Codex fallback mode: local tech portals, general job boards, European remote boards, and recruiting firms such as `ITJobs.pt`, `Teamlyzer Jobs`, `Landing.Jobs`, `EnglishJobs.pt`, `Net-Empregos`, `SAPO Emprego`, `EURES`, `EuroTechJobs`, `Working Nomads Portugal`, `Talent.com Portugal`, `Jobted Portugal`, `Jooble Portugal`, `Randstad Portugal`, `Hays Portugal`, `Adecco Portugal`, `Michael Page Portugal`, and `Robert Walters Portugal` are seeded as manual-only sources until a source proves stable enough for a native adapter. The same fallback path covers public staffing/career boards `TurnKey Staffing`, `CloudDevs`, `Hire With Near`, `weKnow`, `Revelo`, `Awana`, `Tecla`, `VanHack`, `Kake`, and `Zipdev`; `Nir Yu` is covered natively by the existing Teamtailor adapter. Screenshot-sourced portals `DataAnnotation Coding`, `Proxify Careers`, and `RemoteJobsFinder` are also registered, with Proxify kept assisted because it returns an anti-bot response to the Rails worker. Each assisted source carries canonical seed URLs and profile-driven search metadata. `Recrutei` deserves one operational note: the public `/<label>/vacancies` page does not reliably SSR active links, so the adapter uses direct vacancy URLs already persisted by the dashboard and can optionally be bootstrapped with `company_labels` or `vacancy_urls` in the source settings. `Sólides` also deserves one: the public `/vagas` search page is a client-side shell, so the adapter goes straight to the public `apigw.solides.com.br/jobs/v3/portal-vacancies-new/` endpoint and only accepts vacancies whose public detail page is still receiving resumes. `Teamtailor` currently covers `*.teamtailor.com` boards discovered from existing job URLs or manually seeded `board_urls`; custom domains fronted by Teamtailor but without the suffix are still outside this adapter. `SmartRecruiters` goes through the official Posting API because the public job pages are protected by a JS challenge; it trusts `active`, `releasedDate`, and `applyUrl` from the API and is seeded via `company_identifiers`. `Trampos` is driven by the platform's public `api/v2/opportunities` feed instead of its weak term search; when `apply_url` is empty, the canonical detail page itself becomes the applyable link because the candidacy flow is handled inside `trampos.co`. `Coodesh` is driven by the public `sitemaps/jobs.xml` plus the SSR payload embedded in each vacancy page; if the job has no `external_url`, the canonical vacancy page itself becomes the applyable link because the candidacy flow is internal to `coodesh.com`.

`RailsFullstack` is driven primarily by the current remote Rails collection embedded in its SSR payload, which avoids dozens of detail requests per scan. The public sitemap index and each vacancy's `JobPosting` JSON-LD remain as a fallback; that path reads `datePosted`/`validThrough`, caps detail requests with `max_jobs`, and follows the external `Apply now` link when present.

`We Work Remotely` publishes its titles as `Company: Role`, so the adapter splits the company prefix before the policy classifies the role; it also honours `expires_at`, keeps the canonical link on `weworkremotely.com` as the attribution their feed terms ask for, and reads the engineering category feeds configured in `feed_urls`. `Wellfound` (the current home of `angel.co`/AngelList Talent) and `Job Board Search` are assisted instead of native: both answer the Rails worker with a Cloudflare challenge. `Job Board Search` is also a directory of boards rather than a source of vacancies, so its fallback role is to surface new stack-specific boards worth promoting into this catalog, never to ingest listings directly.

`JobLeads Portugal` is assisted for a different reason: its remote listing does embed a readable Nuxt payload, but repeated requests from the Rails worker start returning Cloudflare 503s, the `filter_by_date` parameter is ignored server-side, the returned set skews heavily stale (median around 237 days old, with a single posting inside a 20-day window), and detail pages expose no external apply link — they gate the application behind a JobLeads login. The fallback role is therefore to confirm recency and locate the original posting before anything is ingested.

`GoGloby` is a small curated board (single digits of open roles) discovered through `jobs-sitemap.xml`; recency comes from the sitemap `lastmod` plus each page's `article:modified_time`, and the canonical vacancy URL is also the apply link because applications go through an on-page form rather than an external ATS. Two of its markup quirks are worth knowing: every vacancy page also renders a "More jobs like this" carousel whose `.position-type` nodes describe *other* postings, so the adapter reads the location only from the page header, and the header format is `<contract> / <location>` where the location itself may contain slashes, so only the first separator is split.

Public `Notion` vacancy pages are read through Notion's `loadPageChunk` endpoint, the same public API the browser calls, because the HTML those URLs serve is an empty JavaScript shell. Notion offers no way to enumerate a workspace's public pages — its search endpoint returns nothing without membership and the parent block of a shared page is normally private — so this source is seeded with explicit `page_urls` rather than crawled. Each entry may be a plain URL or a hash with `mirror_of` pointing at the same vacancy on the company's own site; when set, the site URL becomes the canonical identity so the two sources collapse into one job while the Notion page stays the apply link.

`Artificial Intelligence Jobs` is read through its documented public API (`/api/jobs`, see their `/developers` page), filtered to remote roles. Two behaviours are deliberate: the candidate canonicalizes to the employer's own `apply_url` when the board exposes one, so the same vacancy discovered directly through Greenhouse/Lever/Ashby collapses into a single job; and because the list API carries no technology fields, titles that pass the pre-filter earn a bounded number of detail-page fetches (`max_detail_pages`) so the policy has enough context to confirm a stack.

The Google Sheets company lists (`European Tech Companies Visa Sponsorship`, `Remotive Remote Startups`, `100% Remote Hiring Companies`, `Recently Funded Startups`, `Pragmatic Engineer Companies Hiring`) are registered as assisted sources with a distinct role: they list *companies*, not vacancies. Their fallback job is to extract careers pages and promote any board running on an ATS this project already reads natively into that source's settings — which is exactly how the current Greenhouse, Lever, Ashby and SmartRecruiters board lists were expanded.

`Lever` also has one important optimization: the adapter now applies the active profile union policy against the board payload before materializing a candidate. That keeps strong and borderline matches for any configured profile, while avoiding obvious generic roles that do not fit any active radar.

## Main Features

- Rails 8, PostgreSQL, Turbo, Stimulus, Tailwind
- public Farol landing with persisted waitlist capture, request throttling, and optional Resend notification
- session-based private login with server-side expiry (30 days by default, `SESSION_TTL_DAYS`)
- operator role (`admin`) gating source administration and run/backfill screens
- configurable self-registration: open in development, closed by default in production
  (`ALLOW_PUBLIC_REGISTRATION=true` to enable)
- configurable search profiles for stack, title terms, seniority, locality, remote requirement, and women-only affirmative-role eligibility
- filterable and paginated job radar
- profile-scoped job matches and workflow state
- strong vs borderline match classification
- source catalog for ATSs and platforms
- source catalog with latest scan status and coverage counters
- editable source administration, including validated JSON `settings` for adapters that need seeded boards/slugs/queries and explicit Codex fallback flags
- validated native backfill contract: a source can only participate in recurring/manual Rails discovery when its `adapter_key` is supported by the registry
- secure ingestion endpoint with shared bearer token
- deterministic backfill trigger from the Runs screen
- source-scoped backfill triggers from the Runs and Sources screens
- Codex fallback source API for blocked/manual sources that still need assisted discovery, including active profile policy contracts
- native daily discovery scheduled through Solid Queue recurring tasks at `08:30 BRT` (`11:30 UTC`)
- persisted source-level coverage counters and discovered candidate trace
- persisted ATS memory: known board slugs, tokens, and public career pages can be rediscovered from already-ingested job URLs
- Solid Queue worker for async work and recurring cleanup on the primary PostgreSQL database
- Railway-ready Dockerfile and shared `railway.json`

## Core Models

- `Job`: canonical normalized job record with company, title, URLs, source, recency signal, lifecycle state, and raw payload
- `SearchProfile`: user-owned search intent with stacks, target titles, seniority terms, location terms, negative terms, remote requirement, and women-only eligibility preference
- `JobMatch`: profile-specific evaluation of one `Job`, including stack tags, score, reason, eligibility flags, and user workflow state
- `JobSource`: ATS/platform/company catalog used for filters, normalization, and backfill configuration
- `SearchRun`: one Codex ingestion or Rails discovery execution window
- `SearchRunItem`: per-job outcome within a run, including rejections and expirations
- `SourceScan`: one source-level scan inside a `SearchRun`, with coverage counters
- `DiscoveredJob`: one normalized candidate seen during a source scan before final inbox persistence
- `User` / `Session`: operator access to the private dashboard

## Local Setup

Requirements:

- Ruby `3.4.9`
- PostgreSQL

Setup:

```bash
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/rails server
```

Default development login:

```text
email: admin@example.com
password: change-me-now
```

## Verification

```bash
bin/rails test
bin/rubocop
bin/brakeman -q -w2
```

Manual deterministic backfill:

```bash
bin/rails "dashboard:discover[20]"
```

## Evaluate In 5 Minutes

1. Read [docs/architecture.md](docs/architecture.md) for the current system boundaries.
2. Read [docs/engineering-case-study.md](docs/engineering-case-study.md) for the product tradeoffs and why Rails owns the canonical flow.
3. Inspect the shared write boundary in `app/services/job_ingestions/recorder.rb`, the native discovery flow in `app/services/job_discovery/orchestrator.rb`, and the profile policy in `app/services/job_discovery/policy.rb`.
4. Inspect the operational UI boundary in `app/controllers/search_runs_controller.rb` and `app/controllers/sources_controller.rb`.
5. Run the repo-standard verification commands:

```bash
bin/rails test
bin/rubocop
bin/brakeman -q -w2
```

Useful focused tests:

```bash
bin/rails test test/jobs/discover_jobs_run_job_test.rb
bin/rails test test/services/job_discovery/orchestrator_test.rb
bin/rails test test/services/job_ingestions/importer_test.rb
bin/rails test test/controllers/api/v1/job_ingestions_controller_test.rb
bin/rails test test/controllers/sources_controller_test.rb
bin/rails test test/controllers/waitlist_entries_controller_test.rb
```

## Ingestion API

Endpoint:

```text
POST /api/v1/job_ingestions
Authorization: Bearer <INGEST_SHARED_TOKEN>
Content-Type: application/json
```

Accepted payload shape:

```json
{
  "run": {
    "window_label": "24h",
    "trigger_source": "codex_automation",
    "started_at": "2026-06-06T08:30:00-03:00"
  },
  "strong_matches": [
    {
      "title": "Senior Ruby on Rails Engineer",
      "company": "Clicksign",
      "apply_url": "https://clicksign.gupy.io/jobs/11233965",
      "source_url": "https://clicksign.gupy.io/jobs/11233965?jobBoardSource=gupy_public_page",
      "source_name": "Gupy",
      "source_kind": "ats",
      "stack_tags": ["ruby", "rails"],
      "remote_signal": "Remoto Brasil",
      "recency_text": "publicada hoje",
      "published_at": "2026-06-06T10:45:01-03:00",
      "reason": "Titulo senior com Ruby on Rails e remoto BR",
      "score": 97
    }
  ],
  "borderline_matches": [],
  "rejections": []
}
```

Successful responses return the `search_run_id` plus ingestion counters. Rails stores one canonical `Job` and then creates or updates `JobMatch` rows for every active profile whose policy accepts that job. External `match_strength`, `score`, `stack_tags`, and `reason` are treated as hints; Rails reclassifies the payload before persisting final match state.

## Codex Fallback API

Endpoint:

```text
GET /api/v1/codex_fallback_sources
Authorization: Bearer <INGEST_SHARED_TOKEN>
```

This endpoint returns only enabled sources marked with `codex_fallback_enabled=true`, plus active profile policy contracts and the ingestion path. Codex uses this list for a narrow fallback automation: search the blocked sources using the configured profile terms, validate active directly apply-able roles, then post the resulting jobs back to `/api/v1/job_ingestions` with `trigger_source=codex_automation`. The ingestion service re-runs `JobDiscovery::Policy` for each active `SearchProfile` before persisting any final match state.

## Railway Deployment

The repo is configured for multiple Railway services from the same codebase:

- `web`
- `worker`

Shared config lives in [railway.json](railway.json). Both services use the same container image and switch behavior through `APP_SERVICE_ROLE` in [bin/boot-service](bin/boot-service):

- Web: `APP_SERVICE_ROLE=web`
- Worker: `APP_SERVICE_ROLE=worker`

The pre-deploy command runs through `bin/predeploy`, which retries `db:prepare` when Railway boots `web` and `worker` concurrently:

```bash
./bin/predeploy
```

Operational note: if a legacy or manually edited `JobSource` somehow ends up with `supports_backfill=true` and an unsupported `adapter_key`, the source is no longer skipped silently. The next Rails discovery run records a failed `SourceScan` with an explicit adapter error, the source edit form rejects that configuration on save, and the UI now limits adapter selection to the supported registry plus `manual_only`.

Required service variables:

- `RAILS_MASTER_KEY`
- `DATABASE_URL`
- `ADMIN_EMAIL`
- `ADMIN_PASSWORD`
- `INGEST_SHARED_TOKEN`

Useful optional variables:

- `APP_SERVICE_ROLE=web` or `worker`
- `ADMIN_RESET_PASSWORD=1`
- `ALLOW_PUBLIC_REGISTRATION=true` (registration is closed by default in production)
- `SESSION_TTL_DAYS=30` (server-side session expiry window)
- `APP_HOSTS=web-production-b2243.up.railway.app` (comma-separated allowed hosts for DNS rebinding protection)
- `JOB_CONCURRENCY=1`
- `JOB_STALE_AFTER_DAYS=21`

Solid Queue tables live in the main Rails schema because this app uses a single PostgreSQL database in Railway. Recurring tasks are configured in [config/recurring.yml](config/recurring.yml). Rails now enqueues its own daily `24h` discovery run at `11:30 UTC`, which corresponds to `08:30 BRT`. Rails remains the only primary scheduled engine; Codex is a separate fallback path for sources that Rails explicitly marks as blocked or assisted.

The deterministic Rails backfill can already be run manually from the dashboard or via `dashboard:discover`. The Runs screen can launch either a full backfill or a source-scoped backfill, and the Sources screen can do the same right after you change adapter settings. The Sources screen is now the operational place to seed adapter-specific `settings` such as `board_urls`, `company_labels`, `company_slugs`, `company_identifiers`, `search_queries`, and `max_pages`. It is also where blocked sources are marked for Codex fallback with an operator-visible reason, `last_codex_checked_at`, and `last_codex_fallback_at`. `dashboard:seed_sources` is now non-destructive for existing records: it bootstraps missing catalog fields but preserves operator overrides for adapter, priority, enablement, scan window, host/base URL edits, JSON `settings`, and Codex fallback settings. The default catalog now also carries curated starter settings for the sources already validated in this project, so blank production records can immediately bootstrap known `Gupy`, `Recrutei`, `Lever`, `Greenhouse`, `Ashby`, `Inhire`, and `SmartRecruiters` boards without manual surgery. If you need to roll out a new default over an existing source, use an explicit migration or task instead of relying on deploy-time seeding. Codex ingestion remains available as a complementary API path and now has a narrow scheduled fallback role.

Run status semantics for native Rails discovery are:

- `succeeded`: all scanned sources ended in `succeeded` or `exhausted`
- `partial`: at least one source scan failed, but the run still imported or updated jobs
- `failed`: every scanned source failed and nothing was imported or updated

## Known Limits

- The dashboard is still a private operator product, not a public multi-tenant job platform.
- Native Rails discovery does not cover every source in the catalog; some boards still rely on explicit `codex_fallback_enabled` handling or curated `settings`.
- Waitlist capture is a real persisted lead flow, but notification delivery depends on optional Resend configuration.
- The product does not automate applications; it surfaces directly apply-able links and keeps workflow state inside the dashboard.

## Review Notes

Canonical architecture documentation lives in [docs/architecture.md](docs/architecture.md).

The short engineering case study lives in [docs/engineering-case-study.md](docs/engineering-case-study.md).

The QDSAA + thermo review requested for this project lives in [docs/qdsaa-thermo-review.md](docs/qdsaa-thermo-review.md).

The CI/CD process for GitHub Actions and Railway lives in [docs/ci-cd.md](docs/ci-cd.md).

## License

This repository is published under the MIT License. See
[LICENSE.txt](LICENSE.txt).

That keeps the operator workflows, ingestion patterns, and documentation
reusable for study and internal tooling experiments.
