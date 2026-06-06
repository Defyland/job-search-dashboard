# Job Search Dashboard

Rails 8 dashboard for senior Ruby, Ruby on Rails, React, and React Native job discovery. The app still accepts curated Codex ingestion, but it now also owns a first deterministic discovery slice for Rails-driven backfills and recurring scans.

## Architecture

The production flows are:

- `Codex automation -> POST /api/v1/job_ingestions -> Rails persistence and dedupe -> private dashboard`
- `Rails backfill job -> source adapters -> discovered candidates -> Rails persistence and dedupe -> private dashboard`

What Rails owns:

- private authenticated UI
- canonical `Job`, `JobSource`, `SearchRun`, `SearchRunItem`, `SourceScan`, and `DiscoveredJob` records
- dedupe by canonical URL and fingerprint
- user workflow state: `new_match`, `seen`, `applied`, `ignored`
- job lifecycle state: `active`, `expired`
- run history and raw payload traceability
- deterministic source coverage for the adapters already implemented
- policy enforcement for women-only exclusion, title-first seniority matching, and remote compatibility

What Codex owns:

- Google-style discovery across ATSs, remote platforms, and company pages
- validation that the job is still active and directly apply-able
- recency judgment and stack/title matching

What Rails currently discovers by itself:

- `Gupy` company boards already known to the dashboard
- `Recrutei` vacancy pages already known to the dashboard, plus optional company labels or direct vacancy URLs configured in `JobSource.settings`
- `Inhire` career pages discovered from persisted `*.inhire.app/vagas/<jobId>` URLs plus public tenant resolution
- `Lever` company boards discovered from persisted `jobs.lever.co/<company>/<posting>` URLs
- `Greenhouse` boards discovered from persisted `job-boards.greenhouse.io/<board>/jobs/<id>` URLs
- `Ashby` job boards discovered from persisted `jobs.ashbyhq.com/<board>/<posting>` URLs
- `ProgramaThor` remote senior listing pages
- `Remotar` via public jobs API, incluindo links externos para ATSs como `Gupy` e `Inhire`
- `Workable` via public global jobs API

The rest of the catalog is still present for normalization/filtering, but not yet scanned by native Rails adapters. `Recrutei` deserves one operational note: the public `/<label>/vacancies` page does not reliably SSR active links, so the adapter uses direct vacancy URLs already persisted by the dashboard and can optionally be bootstrapped with `company_labels` or `vacancy_urls` in the source settings.

## Main Features

- Rails 8, PostgreSQL, Turbo, Stimulus, Tailwind
- session-based private login
- filterable and paginated job radar
- strong vs borderline match classification
- source catalog for ATSs and platforms
- secure ingestion endpoint with shared bearer token
- deterministic backfill trigger from the Runs screen
- persisted source-level coverage counters and discovered candidate trace
- persisted ATS memory: known board slugs, tokens, and public career pages can be rediscovered from already-ingested job URLs
- Solid Queue worker for async work and recurring cleanup on the primary PostgreSQL database
- Railway-ready Dockerfile and shared `railway.json`

## Core Models

- `Job`: normalized job record with stack tags, score, recency signal, apply URL, raw payload, and user lifecycle state
- `JobSource`: ATS/platform/company catalog used for filters, normalization, and backfill configuration
- `SearchRun`: one Codex ingestion or Rails discovery execution window
- `SearchRunItem`: per-job outcome within a run, including rejections and expirations
- `SourceScan`: one source-level scan inside a `SearchRun`, with coverage counters
- `DiscoveredJob`: one normalized candidate seen during a source scan before final inbox persistence
- `User` / `Session`: operator access to the private dashboard

## Local Setup

Requirements:

- Ruby `3.4.2`
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

Successful responses return the `search_run_id` plus ingestion counters.

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

Required service variables:

- `RAILS_MASTER_KEY`
- `DATABASE_URL`
- `ADMIN_EMAIL`
- `ADMIN_PASSWORD`
- `INGEST_SHARED_TOKEN`

Useful optional variables:

- `APP_SERVICE_ROLE=web` or `worker`
- `ADMIN_RESET_PASSWORD=1`
- `JOB_CONCURRENCY=1`
- `JOB_STALE_AFTER_DAYS=21`

Solid Queue tables live in the main Rails schema because this app uses a single PostgreSQL database in Railway. Recurring tasks are configured in [config/recurring.yml](config/recurring.yml). The main daily search is intentionally not run by Rails; it is driven by the Codex automation and ingested here.

The deterministic Rails backfill can already be run manually from the dashboard or via `dashboard:discover`. Migrating the full daily discovery away from Codex still depends on implementing additional adapters beyond the current `Gupy`, `Recrutei`, `Inhire`, `Lever`, `Greenhouse`, `Ashby`, `ProgramaThor`, `Remotar`, and `Workable` slice.

Run status semantics for native Rails discovery are:

- `succeeded`: all scanned sources ended in `succeeded` or `exhausted`
- `partial`: at least one source scan failed, but the run still imported or updated jobs
- `failed`: every scanned source failed and nothing was imported or updated

## Review Notes

The QDSAA + thermo review requested for this project lives in [docs/qdsaa-thermo-review.md](docs/qdsaa-thermo-review.md).
