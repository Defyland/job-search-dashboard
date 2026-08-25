require "test_helper"

class JobDiscovery::Adapters::GoglobyJobsSitemapAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "discovers vacancies from the jobs sitemap and keeps the on-page apply flow" do
    source_scan = build_source_scan
    sitemap_url = "https://gogloby.com/jobs-sitemap.xml"
    rails_url = "https://gogloby.com/jobs/senior-full-stack-ruby-on-rails-developer"
    stale_url = "https://gogloby.com/jobs/senior-ruby-engineer-stale"
    ignored_url = "https://gogloby.com/jobs/ios-developer"

    sitemap = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>#{rails_url}/</loc><lastmod>2026-08-18T18:57:14+00:00</lastmod></url>
        <url><loc>#{stale_url}/</loc><lastmod>2026-05-01T10:00:00+00:00</lastmod></url>
        <url><loc>#{ignored_url}/</loc><lastmod>2026-08-17T13:47:04+00:00</lastmod></url>
      </urlset>
    XML

    adapter = JobDiscovery::Adapters::GoglobyJobsSitemapAdapter.new(
      fetcher: FakeFetcher.new(
        sitemap_url => sitemap,
        rails_url => job_html(
          title: "Senior Full Stack Ruby on Rails Developer",
          position_type: "Full-time / LATAM Based - Remote",
          modified_time: "2026-08-18T18:57:14+00:00",
          canonical_url: "#{rails_url}/"
        ),
        stale_url => job_html(
          title: "Senior Ruby on Rails Engineer",
          position_type: "Full-time / LATAM Based - Remote",
          modified_time: "2026-05-01T10:00:00+00:00",
          canonical_url: "#{stale_url}/"
        ),
        ignored_url => job_html(
          title: "iOS Developer",
          position_type: "Full-time / US based Austin",
          modified_time: "2026-08-17T13:47:04+00:00",
          canonical_url: "#{ignored_url}/"
        )
      )
    )

    travel_to Time.zone.parse("2026-08-25 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      candidate = candidates.first
      assert_equal "strong", candidate[:classification]
      assert_equal "Senior Full Stack Ruby on Rails Developer", candidate[:title]
      assert_equal "Full-time / LATAM Based - Remote", candidate[:remote_text]
      assert_equal "LATAM Based - Remote", candidate[:location_text]
      assert_equal rails_url, candidate[:canonical_url]
      assert_equal rails_url, candidate[:apply_url]
      assert_equal "senior-full-stack-ruby-on-rails-developer", candidate[:external_job_id]
      assert_equal "gogloby_form", candidate.dig(:payload, :apply_flow)
      assert_equal 4, source_scan.reload.pages_scanned
    end
  end

  test "caps detail requests with max_jobs and prefers the freshest sitemap entries" do
    source_scan = build_source_scan(max_jobs: 1)
    sitemap_url = "https://gogloby.com/jobs-sitemap.xml"
    fresh_url = "https://gogloby.com/jobs/senior-rails-fresh"
    older_url = "https://gogloby.com/jobs/senior-rails-older"

    sitemap = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>#{older_url}/</loc><lastmod>2026-08-12T10:00:00+00:00</lastmod></url>
        <url><loc>#{fresh_url}/</loc><lastmod>2026-08-22T10:00:00+00:00</lastmod></url>
      </urlset>
    XML

    adapter = JobDiscovery::Adapters::GoglobyJobsSitemapAdapter.new(
      fetcher: FakeFetcher.new(
        sitemap_url => sitemap,
        fresh_url => job_html(
          title: "Senior Ruby on Rails Developer",
          position_type: "Full-time / LATAM Based - Remote",
          modified_time: "2026-08-22T10:00:00+00:00",
          canonical_url: "#{fresh_url}/"
        )
      )
    )

    travel_to Time.zone.parse("2026-08-25 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      assert_equal fresh_url, candidates.first[:canonical_url]
      assert_equal 2, source_scan.reload.pages_scanned
    end
  end

  test "ignores the related-jobs carousel when reading the vacancy location" do
    source_scan = build_source_scan
    sitemap_url = "https://gogloby.com/jobs-sitemap.xml"
    hybrid_url = "https://gogloby.com/jobs/senior-rails-hybrid"

    sitemap = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>#{hybrid_url}/</loc><lastmod>2026-08-22T10:00:00+00:00</lastmod></url>
      </urlset>
    XML

    # The real pages render sibling `.position-type` nodes for unrelated
    # postings; the adapter must not read this vacancy's location from them.
    page = <<~HTML
      <html>
        <head>
          <link rel="canonical" href="#{hybrid_url}/">
          <meta property="og:title" content="Senior Ruby on Rails Developer | GoGloby">
          <meta property="article:modified_time" content="2026-08-22T10:00:00+00:00">
        </head>
        <body>
          <div class="block-header">
            <div class="block-header__content">
              <h2 class="h1 block-title">Senior Ruby on Rails Developer</h2>
              <div class="block-description">Full-time / San Francisco, CA (Hybrid - 4 days/week in-office)</div>
            </div>
          </div>
          <h3 class="job-title">About the Role</h3>
          <p>Ruby on Rails product work with a small team.</p>
          <div class="position-cards">
            <div class="position-card"><div class="position-type">Full-time / LATAM Based - Remote</div></div>
          </div>
        </body>
      </html>
    HTML

    adapter = JobDiscovery::Adapters::GoglobyJobsSitemapAdapter.new(
      fetcher: FakeFetcher.new(sitemap_url => sitemap, hybrid_url => page)
    )

    travel_to Time.zone.parse("2026-08-25 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      candidate = candidates.first
      assert_equal "San Francisco, CA (Hybrid - 4 days/week in-office)", candidate[:location_text]
      assert_not_equal "LATAM Based - Remote", candidate[:location_text]
    end
  end

  private
    def build_source_scan(max_jobs: 25)
      source = JobSource.create!(
        name: "GoGloby Test",
        slug: "gogloby-test",
        host: "gogloby.com",
        base_url: "https://gogloby.com/jobs/",
        source_kind: :platform,
        adapter_key: "gogloby_jobs_sitemap",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          "sitemap_url" => "https://gogloby.com/jobs-sitemap.xml",
          "max_jobs" => max_jobs
        }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end

    def job_html(title:, position_type:, modified_time:, canonical_url:)
      <<~HTML
        <html>
          <head>
            <link rel="canonical" href="#{canonical_url}">
            <meta property="og:title" content="#{title} | GoGloby">
            <meta property="article:modified_time" content="#{modified_time}">
          </head>
          <body>
            <h2 class="h1 block-title">#{title}</h2>
            <div class="block-description">#{position_type}</div>
            <h3 class="job-title">About the Role</h3>
            <p>Build and ship a Ruby on Rails product with React on the front end.</p>
            <form id="modal-job-form-content"><input name="email"></form>
          </body>
        </html>
      HTML
    end
end
