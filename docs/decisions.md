# Decision Journal

Running log of every technical decision: what was decided, why, which alternatives were
rejected, and the commit/refs. Newest entries first. One entry per decision.

---

## 2026-09-02 - Native adapter for HireRubyDevs, with a guard for inverted validThrough

**Decision:** Added `hirerubydevs_jobs_sitemap`, discovering through the sitemap rather than the
`/jobs` listing, and ignoring a `validThrough` that is at or before the posting's own `datePosted`.

**Why the sitemap:** the listing is paginated across 230+ pages, while the sitemap carries all 1612
vacancies with a precise `lastmod`. Sorting by `lastmod` and applying the window cutoff there means
recency is decided before any page request, instead of walking pages to find fresh rows.

**Why the validThrough guard:** a live vacancy fetched on 2026-09-02 reported
`datePosted: 2026-09-02T00:49:17Z` with `validThrough: 2026-08-16T06:02:05Z` — expired more than two
weeks *before* it was posted. Other rows on the same board were internally consistent
(posted 08-21, valid through 10-20), so this is a stale field carried into a republished posting, not
a real expiry. Trusting it blindly would have buried an active Cloudflare role posted hours earlier.
A `validThrough` that is genuinely in the past and after the posting date still marks the candidate
`expired` through the same `Policy::Result` path RailsFullstack uses, so the row stays visible with a
reason instead of disappearing.

**Skills field:** the JobPosting block carries `skills` ("rails, ruby") which the prose may never
repeat. It is prepended to the description so the stack signal does not depend on the description
wording.

**Apply route:** `robots.txt` allows `/jobs` but disallows `/jobs/*/apply` and `/jobs/*/website`, so
the vacancy page is both canonical identity and apply link, and only the two-segment `/jobs/<slug>`
path is accepted from the sitemap. Every hop is pinned to `hirerubydevs.com`.

**UNVERIFIED:** the `robots.txt` carries a Cloudflare `Content-Signal:
search=yes,ai-train=no,use=reference` header framed as an Article 4 (EU 2019/790) reservation of
rights. Indexing and linking back is consistent with `search=yes`/`use=reference`, but that is an
engineering reading and the terms of service were not read. Recorded in the README.

**Verification:** 6 new tests covering the skills field reaching the policy, host pinning plus never
requesting the disallowed apply route, window/path filtering before fetch, a genuine expiry, the
inverted-`validThrough` case, and the `max_jobs` budget picking the newest rows. Full suite and
RuboCop green.

---

## 2026-08-27 - Native adapters for HiringCafe and ITJobCafe

**Decision:** Added two native adapters instead of registering either source as assisted:
`hiringcafe_jobs_sitemap` and `itjobcafe_jobs_api`.

**Why (ITJobCafe):** `/JobSearch/RemoteJobs` is an AngularJS shell — the HTML contains
`{{ value.Title }}` and zero vacancy links — and the sitemap lists only static pages, so there was
nothing to scrape. The page's own controller (`/js/NgScripts/JobSearch/jobs.js`) calls
`POST /JobSearch/GetLatestJobs` with `{keywords, location}`; the endpoint answers `200` with plain
JSON, no authentication, and returns the same `BriefInfo` description the detail page renders. One
POST per configured query is therefore enough, with no per-vacancy request and no third-party URL to
follow. Rows repeat across queries, so they are deduped by `ID`.

**Why (HiringCafe):** its search API answers `401` and the UI is client-side, but `robots.txt`
advertises job-posting sitemaps, allows `/job/`, and each vacancy page carries a full schema.org
`JobPosting` block (title, company, `datePosted`, `validThrough`, `jobLocationType`, salary). The
chunks hold ~20k URLs each, so the adapter filters on `lastmod` and on the role encoded in the slug
*before* spending a request, and only then fetches the page.

**Rejected:** marking either source assisted. HiringCafe was 403 behind a Vercel checkpoint on
2026-08-26 and would have been registered as assisted on that evidence; re-probing on 2026-08-27
showed `200` for `robots.txt`, vacancy pages and sitemaps, which makes a native adapter the honest
choice today. The 403 may return, and a failure stays visible as a failed scan.

**Safety:** HiringCafe URLs come from a third-party document, so every request pins the whole
redirect chain to `hiringcafe.com`, and only `/job/<slug>` paths are accepted — the `/viewjob/`,
`/org/`, `/company/`, `/b/` and query-string disallows in their robots are respected. ITJobCafe needs
no pinning because it never follows a URL from the payload.

**UNVERIFIED:** neither site's terms of service were read, and the ITJobCafe endpoint is
undocumented (discovered in the site's own public JS). Recorded in README under "Source provenance
and unverified terms".

**Verification:** 10 new adapter tests (5 each) covering dedupe across queries, window cutoff,
malformed payload isolation, query cap, host pinning, slug pre-filter, expired `validThrough`, and
robots-disallowed paths; full suite and RuboCop green.

---

## 2026-08-26 - Close the remaining review findings: redirect pinning, JSON parsing, EU query hosts

**Decision:** Closed the three findings still open after the previous round.

**Redirect SSRF (real gap):** the AI adapter validated the detail URL's host, but `Fetcher#call`
followed redirects to any host, so an allowed URL that immediately redirected elsewhere still
reached an arbitrary target. `call` now accepts `allowed_hosts` and re-checks *every hop*; the AI
adapter passes its own host. Adapters that do not opt in are unaffected, and `html_document` only
forwards the argument when a caller asks for pinning, so existing fetchers keep their signature.
Verified against a live redirect: `https://example.com/` was refused mid-chain.

**Unguarded `JSON.parse`:** a malformed or HTML page (exactly what the Vercel checkpoint returns)
raised mid-scan and discarded rows already collected. Parsing is now guarded, logs the failure and
ends the scan, keeping the pages that did parse.

**EU hosts in the search index:** `QueryBuilder::TARGETS` still listed only the primary Greenhouse
and Lever hosts, so the site-scoped queries never reached EU boards even after the classifier and
adapters learned those hosts. The three EU hosts are now seeded there too.

**Still UNVERIFIED:** Workable, Recruitee and Personio boards appear in the harvested company
lists and remain ignored by the classifier. The Workable adapter reads a global feed instead of
per-company boards, so supporting them is a design change rather than a host addition.

**Verification:** 308 tests / 2532 assertions green, RuboCop clean, Zeitwerk ok, plus a live
redirect probe. Three new Fetcher tests cover the off-host hop, the same-host hop and the
unpinned default.

**Refs:** app/services/job_discovery/fetcher.rb, app/services/job_discovery/adapters/base.rb,
app/services/job_discovery/adapters/artificialintelligencejobs_api_adapter.rb,
app/services/job_discovery/search_index/query_builder.rb.

---

## 2026-08-26 - Close the review findings on the AI jobs adapter and ATS host parity

**Decision:** Fixed every remaining item raised by the DeepSeek/Grok review, each reproduced on
HEAD before being changed and locked with a regression test.

**AI jobs adapter.** Five defects, all reproduced first:
- `break if candidates.size >= payload["matched"].to_i` truncated the scan whenever `matched` was
  absent (`nil.to_i` is 0, so the guard was always true) or non-numeric. It also compared accepted
  candidates against rows the API offers, so a page of filtered-out roles ended the scan early.
  Paging now tracks rows seen and only trusts a positive integer total.
- `bounded` used `value.presence`, which drops a literal `0`, so `max_detail_pages: 0` was coerced
  to 1 and still fetched a detail page. Numeric input is now parsed explicitly with a `floor:`.
- The detail URL came straight from the third-party payload. A hostile `url` pointed the worker at
  `169.254.169.254` and the response landed in the candidate description. Detail fetches are now
  restricted to https on the board's own host.
- `rescue StandardError` hid every detail failure. It now rescues the expected fetch/parse errors
  and logs them, so a degraded stack signal is visible.
- Detail text is stripped of `script`/`style` and capped at 8k chars.

**ATS host parity.** The classifier accepted `boards.eu.greenhouse.io`, `job-boards.eu.greenhouse.io`
and `jobs.eu.lever.co`, but the adapters' own `HOSTS` constants did not, so an EU URL already stored
by the dashboard never produced a board token. Verified against the live APIs that
`boards-api.greenhouse.io` and `api.lever.co` are region-independent (gocardless, autoscout24,
octoenergy, blablacar, contentsquare all answered 200), so widening the host list is enough; no
regional endpoint is needed.

**Workable in `promotes_to`.** Removed. Workable is scanned through one global feed and exposes no
per-company board setting, so promising it as a promotion target advertised an ingestion path that
does not exist. A test now asserts every `promotes_to` entry actually owns a board-list setting.

**Observability.** `candidates_seen` only counts rows that survived the pre-filter, which made a
quiet aggregator indistinguishable from an empty one. The adapter now records `api_rows_seen`,
`candidates_built`, `candidates_after_dedupe` and `detail_budget_remaining` in the scan metadata.

**UNVERIFIED, not resolved.** No ToS was reviewed for any aggregator or company list. Verified on
2026-08-26 that `artificialintelligencejobs.co` now returns 403 behind a Vercel security checkpoint
for its homepage, robots.txt and API, so the source it was integrated from is currently blocked; the
adapter surfaces that as a failed scan rather than an empty one. Documented in the README with the
next delimited step.

**Verification:** 303 tests / 2517 assertions, RuboCop clean on 234 files, Zeitwerk ok, Brakeman 0
warnings.

**Refs:** app/services/job_discovery/adapters/artificialintelligencejobs_api_adapter.rb,
app/services/job_discovery/adapters/{greenhouse_boards_api,lever_company_boards}_adapter.rb,
app/services/job_sources/catalog.rb, README.md.

---

## 2026-08-26 - AI jobs board blocked; round closure and residual risks

**Decision:** Flipped `artificial-intelligence-jobs` from a native adapter to an assisted
(Codex fallback) source, and recorded the verification status of every item raised in this round.

**Why the flip:** one day after the adapter shipped, the whole host began answering `403` behind a
Vercel Security Checkpoint — `/api/jobs`, the vacancy detail pages and even `robots.txt`, for the
project's bot user agent, a plain browser user agent and no user agent at all. A native scan can
only fail, so the source now goes through assisted discovery. The adapter and its tests stay in
the repository and `settings.native_adapter_key` records how to flip it back if the checkpoint is
lifted; no code needs to change for that.

**Failure mode is safe:** with the source still native, a scan raised `Fetcher::RequestError`,
which the orchestrator catches per source-scan and reports as a failed scan (`partial` run), so a
blocked source never aborted the whole discovery run.

**Closed in this round (verified):**
- SSRF on detail enrichment: the third-party `url` is now validated against the board host before
  any fetch, with a regression test using a link-local address.
- Pagination: `matched` counts rows offered by the API, not rows accepted by the policy; the scan
  now stops on a short page or once every advertised row was seen, and tolerates a missing or
  non-numeric `matched`.
- `max_detail_pages: 0` is honoured literally instead of being coerced to 1.
- Detail fetch failures are logged instead of silently swallowed; scripts/styles are stripped and
  the description is capped at 8k characters.
- Regional ATS hosts: EU Greenhouse and EU Lever URLs now feed autodiscovery in both the URL
  classifier and the adapters themselves. Verified live that EU-harvested boards resolve on the
  shared APIs (autoscout24 47 jobs, gocardless 25, octoenergy 132, contentsquare 26).
- Re-seeding: curated board lists are merged as a union, so a catalog expansion reaches an existing
  database instead of losing to the stored value.
- Cost per scan: the four ATS sources total 59 boards at roughly one request each, about 24s of
  throttle for that group at the default 0.4s interval.

**UNVERIFIED / residual risks:**
- Workable, Recruitee and Personio URLs appear in the harvested company lists but are still ignored
  by the URL classifier, so those boards are silently dropped during search-index seeding. The
  Workable adapter reads a global feed rather than per-company boards, so wiring them needs a
  design decision, not a one-line host addition.
- Whether the AI board's checkpoint is permanent or transient is unknown; it was reachable the day
  before.
- The Google Sheets company lists are point-in-time snapshots. `docs.google.com/robots.txt` allows
  the document paths in use, but the sheets' own terms of reuse were not audited.
- Recall of the shared policy against AI-heavy boards was not measured; the observation that a
  Ruby/Rails profile accepted none of 49 AI roles is expected filtering, not a proven recall loss.

**Verification:** 303 tests / 2517 assertions green, RuboCop clean over 234 files, Zeitwerk ok,
plus live probes of the blocked host, the EU ATS boards and an end-to-end scan of harvested boards.

**Refs:** app/services/job_sources/catalog.rb,
app/services/job_discovery/adapters/artificialintelligencejobs_api_adapter.rb,
app/services/job_discovery/adapters/{greenhouse_boards_api,lever_company_boards}_adapter.rb.

---

## 2026-08-26 - Make curated ATS board lists additive on re-seed

**Decision:** `JobSources::Catalog.seed!` now unions the four curated ATS board lists
(`board_tokens`, `board_slugs`, `company_slugs`, `company_identifiers`) instead of letting the
stored value win. Every other setting keeps the previous behaviour, where an operator override
beats the catalog default.

**Why (P0 found in review):** `apply_defaults!` merged with `catalog.deep_merge(stored)`, so on a
database that already had a row the stored array always won. Reproduced: seeding an existing row
holding the old lists left Lever at 4 slugs and Greenhouse at 2 — none of the 50 boards harvested
from the company lists reached it. The catalog test passed only because it started from an empty
database, which hid the regression. `bin/predeploy` runs `dashboard:seed_sources`, so production
would have deployed the code without ever gaining the boards.

**Why only these four keys:** they are append-only inventories of employer boards, and the whole
point of harvesting company lists is that they grow. Scalars such as `max_pages` or an edited
`sitemap_url` stay operator-owned, so widening the rule would silently revert deliberate tuning.

**Tradeoffs accepted:** a board removed from the catalog is no longer dropped from an existing
row by re-seeding; retiring one now needs an explicit migration or operator edit. The union keeps
catalog order first and appends operator entries, so ordering is stable across runs.

**Verification:** two regression tests (existing row with a custom token, and seeding twice for
idempotence) plus a real `dashboard:seed_sources` run against a pre-populated database, which took
Lever 3 -> 24 and Greenhouse 1 -> 27 while preserving `operator-custom`.

**Refs:** app/services/job_sources/catalog.rb, test/models/job_source_test.rb.

---

## 2026-08-26 - Harvest ATS boards from company lists; add the AI jobs aggregator

**Decision:** Added a native adapter for `artificialintelligencejobs.co`, registered the five
Google Sheets company lists as assisted discovery sources, widened the URL classifier to regional
ATS hostnames, and seeded 50 live ATS boards harvested from those sheets into the existing
Greenhouse, Lever, Ashby and SmartRecruiters sources.

**Why the sheets are not job sources:** all five list *companies with careers pages*, not
vacancies. Reading them as job boards would produce nothing. Their real value is that they contain
136 URLs on ATS platforms this project already reads natively, so the sheets became a discovery
input feeding the existing adapters instead of a new ingestion path.

**Only live boards were seeded:** each of the 136 candidates was probed against its ATS API before
being added. 50 answered with at least one open role (Greenhouse 25, Lever 19, Ashby 5,
SmartRecruiters 1) totalling ~4,370 open jobs; the rest were dead tokens or empty boards and were
dropped rather than inflating the catalog with sources that never return anything.

**Classifier gap found:** the sheets exposed `boards.eu.greenhouse.io`, `job-boards.eu.greenhouse.io`,
`jobs.eu.lever.co` and `careers.smartrecruiters.com`, which the classifier silently ignored, so
European boards were being discarded during search-index seeding. Those hosts are now recognised.

**AI board specifics:** the API returns the employer's real `apply_url`, so candidates canonicalize
to the original ATS posting and dedupe against the same vacancy found directly. The list payload
carries no technology fields, which made the policy reject nearly everything for lack of stack
context; titles passing the pre-filter now earn a bounded number of detail fetches
(`max_detail_pages`) to recover that signal.

**Tradeoffs accepted:** harvested board lists are a point-in-time snapshot and will decay; boards
that go quiet simply return nothing rather than erroring. The detail fetches add traffic, so they
are capped and only spent on titles that already look relevant.

**Verification:** four adapter tests, classifier tests for the regional hosts, catalog tests for
the new sources and merged board lists, plus live smokes against the AI API and all four ATS APIs.

**Refs:** app/services/job_discovery/adapters/artificialintelligencejobs_api_adapter.rb,
app/services/job_discovery/search_index/url_classifier.rb, app/services/job_sources/catalog.rb.

---

## 2026-08-25 - Read public Notion job pages through Notion's public page API

**Decision:** Added a generic `notion_public_pages` adapter that resolves vacancies published as
public Notion pages, seeded with the GoGloby Rails role. `JobDiscovery::Fetcher` gained a `post`
method so the call reuses the existing throttling, retry and backoff policy.

**Why:** Notion serves those URLs as an empty JavaScript shell ("JavaScript must be enabled"), so
HTML parsing is useless, but the public `loadPageChunk` endpoint returns the full block tree with
no authentication for a page shared with public read access, including title, body and timestamps.

**Discovery is seeded, not crawled:** Notion exposes no enumeration path for a workspace's public
pages. The workspace search endpoint returns zero results without membership, the shared page's
parent block is private, `gogloby.notion.site/sitemap.xml` is Notion's own marketing sitemap, and
none of the eight vacancies on gogloby.com link to Notion. So the source takes explicit `page_urls`.

**Dedupe:** the requested page is the same vacancy already discovered on gogloby.com, and the
fingerprint is built from company, title, canonical host and external id, so it would have been
imported twice — breaking the product's "zero duplicates" promise. A `page_urls` entry may now
carry `mirror_of`; when present the origin site URL supplies the canonical URL and external id,
while the Notion page remains the apply link. Verified live: both sources now yield an identical
fingerprint.

**Tradeoffs accepted:** `loadPageChunk` is an internal-but-public API and could change shape; the
adapter fails soft on unparseable payloads. New Notion vacancies must be added to `page_urls` by
hand, which is acceptable for a source that cannot be enumerated at all.

**Verification:** Three adapter tests, two new Fetcher tests for the POST path, and a live smoke
that classified the requested Rails role as strong with the correct date and description.

**Refs:** app/services/job_discovery/adapters/notion_public_pages_adapter.rb,
app/services/job_discovery/fetcher.rb, app/services/job_sources/catalog.rb.

---

## 2026-08-25 - Add native GoGloby discovery

**Decision:** Added a native `GoGloby` adapter driven by the site's dedicated `jobs-sitemap.xml`
and its server-rendered vacancy pages. The canonical vacancy URL doubles as the apply link.

**Why:** GoGloby exposes a jobs-only sitemap with per-vacancy `lastmod`, allows crawling in
`robots.txt`, and answers the Rails worker without any challenge. The board is small and recent
(8 live roles, all within weeks), so a bounded native scan is cheap and the shared policy can
classify the roles directly.

**Tradeoffs accepted:** Applications are submitted through an on-page WordPress form, so there is
no external ATS link to canonicalize to; the vacancy URL is the applyable destination. The board
is small enough that `max_jobs` mostly guards against future growth rather than current volume.
Vacancy slugs do not always match the current title (`/jobs/ios-developer` now serves a Senior
Full Stack AI Engineer role), so titles are read from the page instead of the URL.

**Two markup traps found during live verification:** every vacancy page renders a "More jobs like
this" carousel whose `.position-type` nodes belong to *other* postings, which made a hybrid San
Francisco role report itself as LATAM remote; the location is now read only from the page header.
And the header reads `<contract> / <location>` where the location may itself contain a slash
(`4 days/week`), so only the first separator is split. Both are covered by regression tests.

**Verification:** Three adapter tests plus a live smoke that returned 5 vacancies over 9 requests,
with the requested Rails role classified strong and the hybrid role correctly rejected as non-remote.

**Refs:** app/services/job_discovery/adapters/gogloby_jobs_sitemap_adapter.rb,
app/services/job_discovery/registry.rb, app/services/job_sources/catalog.rb.

---

## 2026-08-25 - Register JobLeads Portugal as an assisted source

**Decision:** Registered `JobLeads Portugal` (`/pt/jobs?filter_by_remote=remote`) as a Codex
fallback aggregator instead of writing a native adapter, and routed it through the search index
like the other assisted Portugal sources.

**Why:** The listing page does embed a machine-readable Nuxt payload with title, company, salary,
location and `validFrom`, so a native adapter was technically possible. Four findings ruled it out:
repeated fetches from the Rails worker returned Cloudflare 503s, the `filter_by_date` filter was
ignored server-side, the returned set was overwhelmingly stale (median ~237 days, only 1 of 25
inside a 20-day window, and 1 of 10 policy matches), and detail pages carry no external apply link
because JobLeads gates the application behind its own login.

**Tradeoffs accepted:** Discovery through this source needs a Codex pass to confirm recency and to
find the original posting, which is slower than a native scan. In exchange the radar avoids
ingesting long-expired vacancies whose only application path is a JobLeads account. If they ever
expose a dated feed or an external apply URL, the payload shape is already understood and a native
adapter becomes cheap to add.

**Verification:** Catalog test for the new source, plus live probes of the listing page, a detail
page, and the date-filtered variants through the project's own HTTP client.

**Refs:** app/services/job_sources/catalog.rb,
app/services/job_discovery/search_index/query_builder.rb.

---

## 2026-08-22 - Add We Work Remotely natively; Wellfound and Job Board Search assisted

**Decision:** Added a native `We Work Remotely` adapter over its public category RSS feeds, and
registered `Wellfound` (angel.co/AngelList Talent) and `Job Board Search` as Codex fallback
sources. `Himalayas` and `Remotive` were already native and were left untouched.

**Why:** WWR publishes a complete, auth-free RSS feed per category with company, region,
employment type, publication date and expiry, which is enough for deterministic Rails discovery.
`angel.co` now redirects to `wellfound.com`, and both Wellfound and Job Board Search answer the
Rails worker with a Cloudflare challenge, so a native adapter would be unreliable by construction.

**Tradeoffs accepted:** WWR titles arrive as `Company: Role`, so the adapter splits the prefix
before classification; a role legitimately containing a colon would lose the fragment before it.
Feed coverage is scoped to the engineering categories in `feed_urls` instead of the firehose feed,
which keeps request volume low but excludes non-engineering roles. Job Board Search is a directory
of boards, not of vacancies, so its fallback role is to surface boards worth promoting into the
catalog rather than to ingest listings.

**Verification:** Adapter and catalog tests, plus a live smoke against the real feeds that returned
23 candidates over 4 requests with company/title split correctly on every row.

**Refs:** app/services/job_discovery/adapters/weworkremotely_rss_adapter.rb,
app/services/job_discovery/registry.rb, app/services/job_sources/catalog.rb.

---

## 2026-08-19 - Add native RailsFullstack discovery

**Decision:** Added a native `RailsFullstack` adapter backed primarily by the site's SSR remote
Rails collection. Its embedded job payload supplies fresh roles and external application links in
one request. The sitemap index and SSR `JobPosting` detail pages remain a fallback with a bounded
`max_jobs` detail-page budget.

**Why:** `railsfullstack.com` exposes a stable public sitemap and server-rendered vacancy metadata,
while its RSS endpoints are unavailable. Using the sitemap avoids search scraping and lets the
shared policy decide which remote roles belong in the radar.

**Tradeoffs accepted:** The collection payload is an application-level contract and may change;
the sitemap fallback preserves discovery if it does. Sitemap `lastmod` is only a discovery hint
and may refresh independently of the posting date, so the fallback validates `datePosted` and
`validThrough` on each detail page. The default detail budget is 40 jobs per fallback scan.

**Verification:** Focused adapter/catalog tests, RuboCop on the touched Ruby files, and live
smoke checks against the sitemap index and a JSON-LD vacancy page.

**Refs:** app/services/job_discovery/adapters/railsfullstack_jobs_sitemap_adapter.rb,
app/services/job_discovery/registry.rb, app/services/job_sources/catalog.rb.

---

## 2026-08-19 - Native Loxo/Luflox/Rails discovery and stack-specific source routing

**Decision:** Added native adapters for the official Rails Job Board RSS feed, public Loxo
career boards (seeded with FitNext), and Luflox's public Firestore positions feed. Nir Yu is
seeded through the existing Teamtailor adapter. RemoteYeah is integrated through its public RSS
feed, with supplied job pages retained as seeds for postings that have aged out of the feed.
Language/framework-specific portals are
registered as assisted sources with explicit stack affinity, and search-index queries now skip
ecosystem boards that do not match the active profile's stack.

**Why:** General aggregators miss high-signal community boards, while the supplied Loxo and
Luflox links expose stable public data that can participate in deterministic Rails discovery.
Stack affinity prevents wasteful queries such as searching a Rust-only board for React roles.

**Tradeoffs accepted:** Boards without a stable public feed remain in Codex fallback mode and
must be checked for recency and canonicalized to the original application page. Loxo relative
posting ages are approximate; Luflox depends on its intentionally public Firestore collection.
DataAnnotation is retained as a distinct AI-evaluation work platform rather than treated as a
normal employer board, and Proxify remains assisted because the Rails client receives a 403.

**Verification:** Adapter, catalog, query-routing, and existing BeBee regression tests cover the
new contracts. Live endpoint smoke checks are recorded in the implementation handoff.

**Refs:** app/services/job_discovery/adapters/{rails_jobs_rss,loxo_job_board,luflox_positions}_adapter.rb,
app/services/job_sources/catalog.rb, app/services/job_discovery/search_index/query_builder.rb.

---

## 2026-08-17 - Native adapters for international remote boards (RemoteOK, Remotive, Himalayas, beBee)

**Decision:** Added four native discovery adapters for international/BR remote job feeds:
RemoteOK (public global JSON API), Remotive (public remote jobs API), Himalayas (public JSON
API with pagination), and beBee BR (profile-driven search pages parsed from the embedded
Next.js payload). Each source is seeded in the catalog with backfill enabled, registered in the
adapter registry, and covered by adapter tests.

**Why:** The dashboard already covered BR ATS/platforms well but missed global remote boards
with public, stable, auth-free feeds, which surfaced jobs that the native coverage did not
include.

**Tradeoffs accepted:** beBee disallows /api/ and query URLs in its robots.txt, so the adapter
keeps request volume low (one page per configured query term, throttled by the shared
Fetcher); RemoteOK's API terms require attribution/link-back, so the source stays visible in
the dashboard. Himalayas' feed carries a placeholder company name, so the company slug is used
as the display name.

**Refs:** app/services/job_discovery/adapters/{remoteok_jobs_api,remotive_remote_jobs,himalayas_jobs_api,bebee_jobs_page}_adapter.rb,
app/services/job_discovery/registry.rb, app/services/job_sources/catalog.rb.

---

## 2026-08-15 - Security hardening round (dependencies, operator role, sessions, hosts, CSP)

**Decision:** Applied the security adjustments from the read-only audit of the public repo:
updated vulnerable gems (json, loofah, rails-html-sanitizer, rails patch), added an `admin`
flag gating `Sources`/`SearchRuns`, made self-registration configurable (closed by default in
production), added server-side session expiry (`expires_at`, default 30 days), enabled host
authorization with an `APP_HOSTS` allowlist, enabled a Content-Security-Policy with script
nonces, and removed `--ensure-latest` from `bin/brakeman` so local scans are reproducible.

**Why:** The audit found known-vulnerable gems that kept CI red (blocking the automated Railway
deploy), open registration with no roles that contradicted the documented "private operator
dashboard" trust boundary, sessions that never expired, no DNS-rebinding protection, and no CSP.

The follow-up dependency audit on 2026-08-19 also upgraded `mail` from 2.9.0 to 2.9.1
(and its compatible `net-imap` release) to close GHSA-mvxr-6m87-mv2q; Bundler Audit is
now clean.

**Tradeoffs accepted:** CSP allows `style-src 'unsafe-inline'` because the views use inline
`style` attributes; script nonces cover the inline landing script. Host authorization can return
403 for unknown hosts (custom domains must be added to `APP_HOSTS`). Session expiry requires
re-login after the window; `SESSION_TTL_DAYS` tunes it.

**Refs:** `Gemfile.lock`, `db/migrate/20260815090000_add_admin_to_users.rb`,
`db/migrate/20260815100000_add_expiry_to_sessions.rb`, `app/controllers/concerns/authentication.rb`,
`config/environments/production.rb`, `config/initializers/content_security_policy.rb`.

---

## 2026-06-29 - Publish the operator repo under the MIT License

**Decision:** Added `LICENSE.txt` and a README license section so the dashboard,
its case study, and its operational notes are intentionally reusable.

**Why:** The repo is now public and already carries architecture notes, CI/CD
guidance, and learning-oriented decisions. Leaving it under default copyright
would keep the study value visible but the reuse boundary ambiguous.

**Tradeoffs accepted:** A permissive license allows downstream forks to diverge
without upstream contribution. That is acceptable here because the goal is to
maximize learning and portfolio utility, not enforce reciprocal publication.

**Refs:** `LICENSE.txt`, `README.md`.

---

## 2026-06-29 — Prove the ingestion rejection contract at the request boundary

**Decision:** Added request-level proof for the two `POST /api/v1/job_ingestions` rejection paths that
matter most to the trust boundary: invalid bearer auth returns `401`, and malformed job payloads return
the controller's `422 invalid_ingestion_payload` response instead of blowing up inside the importer.

**Why:** The repo already had happy-path ingestion proof and service-level coverage, but a reviewer still
had to infer that the HTTP edge rejected bad callers cleanly. That was the narrow remaining gap in the
public technical story.

**Rejected:** broader auth/fallback test expansion, shared test helpers, or controller refactors. The
smallest honest improvement was to harden the importer's payload validation and prove the resulting
request contract directly.

**Verification:** targeted request/importer tests, full `bin/rails test`, focused system-test rerun after
one flaky Selenium failure in `bin/ci`, and the rest of the repo-standard quality gates.

**Refs:** `app/services/job_ingestions/importer.rb`,
`test/controllers/api/v1/job_ingestions_controller_test.rb`,
`test/services/job_ingestions/importer_test.rb`,
`docs/architecture.md`, `docs/engineering-case-study.md`.

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
