# Engineering Case Study

## Problem

Generic job boards are noisy, duplicated, and operationally opaque. This product exists to prove a different shape:

- keep one canonical job record even when sources overlap;
- keep one explicit per-profile match record instead of burying fit inside ad hoc filters;
- let Rails own the durable workflow even when some sources need assisted fallback discovery;
- keep source operations visible enough that a reviewer can inspect coverage, failures, and accepted tradeoffs.

## Why Rails

Rails fits the real problem better than a scraping-first stack:

- the product needs persistent domain state, not just one-off extraction;
- the operator UI, source admin, runs history, and workflow state are first-class features;
- background jobs and recurring discovery matter, but they stay legible with Solid Queue and Active Job;
- the public landing and waitlist are lightweight enough for server-rendered Rails, not a separate frontend.

The repo leans on Rails for delivery speed, but the important logic stays inspectable in services and explicit models.

## Main Technical Choices

### Rails owns the canonical truth, Codex owns only fallback discovery

Native adapters and Codex fallback both write through the same ingestion boundary. That prevents external automation from becoming the source of truth for `score`, `reason`, or `match_strength`.

### Match jobs per profile, not globally

`Job` is global, `SearchProfile` expresses operator intent, and `JobMatch` stores the per-profile decision plus workflow state. This turns the app into a configurable radar instead of a flat inbox.

### Treat source operations as product surface

`JobSource`, `SourceScan`, `DiscoveredJob`, `SearchRun`, and the Sources/Runs screens make source coverage inspectable. This is why the repo reads like product work instead of a pile of scrapers.

### Keep the deployed shape intentionally small

One codebase, one PostgreSQL database, one Railway image, and separate `web`/`worker` roles are enough to demonstrate scheduling, ingestion, admin flows, and deployment discipline without inventing extra infrastructure.

### Make the public surface honest

The Farol landing is public, but the dashboard remains private. The waitlist is a real persisted capture flow with throttling and optional Resend notification, not a dead marketing form.

## Reviewer Fast Path

A reviewer can validate the main technical claims quickly by reading:

1. `docs/architecture.md`
2. `app/services/job_discovery/orchestrator.rb`
3. `app/services/job_ingestions/recorder.rb`
4. `app/services/job_discovery/policy.rb`
5. `app/controllers/search_runs_controller.rb`
6. `app/controllers/sources_controller.rb`
7. `test/services/job_discovery/orchestrator_test.rb`
8. `test/services/job_ingestions/importer_test.rb`
9. `test/controllers/sources_controller_test.rb`
10. `test/controllers/waitlist_entries_controller_test.rb`

Then run:

```bash
bin/rails test
bin/rubocop
bin/brakeman -q -w2
```

## Risks Accepted

- Native Rails discovery still does not cover every board in the catalog.
- Some source integrations depend on curated `settings` or Codex fallback because the public web surface is unstable or hostile to the worker profile.
- The deployed product is intentionally operator-scale; it does not prove multi-tenant throughput.
- Waitlist notification is complementary and may degrade to persisted-only capture when Resend is not configured.
- Automated applications remain out of scope.

## Outcome

The result is a Rails product asset that demonstrates:

- explicit source-operations modeling;
- a shared ingestion trust boundary for native and assisted discovery;
- per-profile matching instead of one-size-fits-all ranking;
- honest deployment and background-job operations on Railway;
- a public narrative that matches the real code and tests.
