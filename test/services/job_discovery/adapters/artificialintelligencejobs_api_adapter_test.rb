require "test_helper"

class JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :urls, :detail_urls

    def initialize(pages, detail_body: nil)
      @pages = pages
      @detail_body = detail_body
      @urls = []
      @detail_urls = []
    end

    def call(url, limit: 5, headers: {}, allowed_hosts: nil)
      unless url.include?("/api/jobs")
        @detail_urls << url
        raise JobDiscovery::Fetcher::RequestError.new("detail unavailable", code: 500) if @detail_body == :raise

        return @detail_body.to_s
      end

      @urls << url
      @pages.shift || { jobs: [], matched: 0 }.to_json
    end
  end

  test "keeps the employer apply url as canonical so the aggregator dedupes against the ATS" do
    source_scan = build_source_scan
    page = {
      "matched" => 2,
      "jobs" => [
        {
          "title" => "Senior Ruby on Rails Engineer",
          "company" => "Acme AI",
          "location" => "US - Remote",
          "remote" => true,
          "category" => "Engineering",
          "level" => "Senior",
          "region" => "US",
          "salary" => "$200K",
          "posted" => "2026-08-24",
          "url" => "https://artificialintelligencejobs.co/jobs/acme-senior-rails-abc123",
          "apply_url" => "https://jobs.ashbyhq.com/acme/rails-role"
        },
        {
          "title" => "Junior Ruby Developer",
          "company" => "Ignored",
          "posted" => "2026-08-25",
          "url" => "https://artificialintelligencejobs.co/jobs/ignored-junior",
          "apply_url" => "https://jobs.ashbyhq.com/ignored/junior"
        }
      ]
    }.to_json
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher: FakeFetcher.new([ page ]))

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      candidate = candidates.first
      assert_equal "strong", candidate[:classification]
      assert_equal "Acme AI", candidate[:company_name]
      assert_equal "https://jobs.ashbyhq.com/acme/rails-role", candidate[:canonical_url]
      assert_equal "https://jobs.ashbyhq.com/acme/rails-role", candidate[:apply_url]
      assert_equal "https://artificialintelligencejobs.co/jobs/acme-senior-rails-abc123", candidate[:source_url]
      assert_equal "Remote | US - Remote", candidate[:remote_text]
    end
  end

  test "falls back to the board url when the aggregator has no employer link" do
    source_scan = build_source_scan
    page = {
      "matched" => 1,
      "jobs" => [ {
        "title" => "Senior Ruby on Rails Engineer",
        "company" => "Acme AI",
        "location" => "Remote",
        "remote" => true,
        "posted" => "2026-08-24",
        "url" => "https://artificialintelligencejobs.co/jobs/acme-senior-rails-abc123",
        "apply_url" => nil
      } ]
    }.to_json
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher: FakeFetcher.new([ page ]))

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidate = adapter.scan(source_scan:, window_days: 20).first

      assert_equal "https://artificialintelligencejobs.co/jobs/acme-senior-rails-abc123", candidate[:canonical_url]
      assert_equal "acme-senior-rails-abc123", candidate[:external_job_id]
    end
  end

  test "requests the remote-only filter and paginates with offset" do
    source_scan = build_source_scan(max_pages: 2, page_size: 2)
    fresh = ->(suffix) {
      {
        "title" => "Senior Ruby on Rails Engineer #{suffix}",
        "company" => "Acme AI",
        "location" => "Remote",
        "remote" => true,
        "posted" => "2026-08-24",
        "url" => "https://artificialintelligencejobs.co/jobs/acme-#{suffix}",
        "apply_url" => "https://jobs.ashbyhq.com/acme/#{suffix}"
      }
    }
    pages = [
      { "matched" => 4, "jobs" => [ fresh.call("a"), fresh.call("b") ] }.to_json,
      { "matched" => 4, "jobs" => [ fresh.call("c"), fresh.call("d") ] }.to_json
    ]
    fetcher = FakeFetcher.new(pages)
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 4, candidates.size
      assert_equal 2, fetcher.urls.size
      assert fetcher.urls.all? { |url| url.include?("remote=true") }
      assert_includes fetcher.urls.first, "offset=0"
      assert_includes fetcher.urls.last, "offset=2"
      assert_equal 2, source_scan.reload.pages_scanned
    end
  end

  test "enriches the description from the detail page within the configured budget" do
    source_scan = build_source_scan(max_detail_pages: 1)
    page = {
      "matched" => 2,
      "jobs" => [
        {
          "title" => "Senior Ruby on Rails Engineer",
          "company" => "Acme AI",
          "location" => "Remote",
          "remote" => true,
          "category" => "Engineering",
          "posted" => "2026-08-24",
          "url" => "https://artificialintelligencejobs.co/jobs/acme-one",
          "apply_url" => "https://jobs.ashbyhq.com/acme/one"
        },
        {
          "title" => "Senior Ruby on Rails Developer",
          "company" => "Acme AI",
          "location" => "Remote",
          "remote" => true,
          "posted" => "2026-08-24",
          "url" => "https://artificialintelligencejobs.co/jobs/acme-two",
          "apply_url" => "https://jobs.ashbyhq.com/acme/two"
        }
      ]
    }.to_json
    fetcher = FakeFetcher.new([ page ], detail_body: "<html><body>We build with Ruby on Rails and React.</body></html>")
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 2, candidates.size
      # Only the first candidate fits the detail budget.
      assert_equal 1, fetcher.detail_urls.size
      assert_includes candidates.first[:description], "Ruby on Rails and React"
      assert_not_includes candidates.second[:description], "Ruby on Rails and React"
      # The transient budget marker must not leak into the persisted candidate.
      assert_not candidates.first.key?(:fetched_detail)
    end
  end

  test "keeps paginating when the API omits or corrupts matched" do
    source_scan = build_source_scan(max_pages: 3, page_size: 2)
    # No `matched` on page one, a non-numeric value on page two: neither may be
    # read as a stop signal.
    pages = [
      { "jobs" => [ api_job("a"), api_job("b") ] }.to_json,
      { "matched" => "many", "jobs" => [ api_job("c"), api_job("d") ] }.to_json,
      { "matched" => 6, "jobs" => [ api_job("e") ] }.to_json
    ]
    fetcher = FakeFetcher.new(pages)
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 5, candidates.size
      assert_equal 3, fetcher.urls.size
    end
  end

  test "stops once every advertised row has been seen even if most are filtered out" do
    source_scan = build_source_scan(max_pages: 4, page_size: 2)
    # `matched` counts rows offered by the API, not rows the policy accepted.
    pages = [
      { "matched" => 4, "jobs" => [ api_job("a"), rejected_job("junior-one") ] }.to_json,
      { "matched" => 4, "jobs" => [ rejected_job("junior-two"), api_job("b") ] }.to_json,
      { "matched" => 4, "jobs" => [ api_job("c") ] }.to_json
    ]
    fetcher = FakeFetcher.new(pages)
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 2, candidates.size
      assert_equal 2, fetcher.urls.size, "must stop after the 4 advertised rows were seen"
    end
  end

  test "max_detail_pages set to zero disables detail fetching entirely" do
    source_scan = build_source_scan(max_detail_pages: 0)
    fetcher = FakeFetcher.new([ { "matched" => 1, "jobs" => [ api_job("a") ] }.to_json ], detail_body: "<html><body>Ruby on Rails</body></html>")
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      assert_empty fetcher.detail_urls, "a configured 0 must not be coerced to 1"
    end
  end

  test "refuses to fetch a detail page outside the board host" do
    source_scan = build_source_scan(max_detail_pages: 5)
    hostile = api_job("a").merge("url" => "http://169.254.169.254/latest/meta-data/")
    fetcher = FakeFetcher.new([ { "matched" => 1, "jobs" => [ hostile ] }.to_json ], detail_body: "<html><body>internal secret</body></html>")
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_empty fetcher.detail_urls, "a third-party url must not steer the worker"
      assert_not_includes candidates.first[:description].to_s, "internal secret"
    end
  end

  test "logs a failed detail fetch instead of swallowing it" do
    source_scan = build_source_scan(max_detail_pages: 5)
    fetcher = FakeFetcher.new([ { "matched" => 1, "jobs" => [ api_job("a") ] }.to_json ], detail_body: :raise)
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher:)
    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    begin
      travel_to Time.zone.parse("2026-08-26 12:00:00") do
        candidates = adapter.scan(source_scan:, window_days: 20)

        assert_equal 1, candidates.size, "the candidate still survives without the detail"
      end
    ensure
      Rails.logger = original_logger
    end

    assert_includes log.string, "detail fetch failed", "failure must be observable"
  end

  test "strips scripts and caps the description length" do
    source_scan = build_source_scan(max_detail_pages: 5)
    noisy = "<html><body><script>window.secret = 1</script>" + ("Ruby on Rails " * 2000) + "</body></html>"
    fetcher = FakeFetcher.new([ { "matched" => 1, "jobs" => [ api_job("a") ] }.to_json ], detail_body: noisy)
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      description = adapter.scan(source_scan:, window_days: 20).first[:description]

      assert_not_includes description, "window.secret"
      assert_operator description.length, :<=, JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter::MAX_DESCRIPTION_CHARS
    end
  end

  test "a malformed page ends the scan without losing rows already collected" do
    source_scan = build_source_scan(max_pages: 3, page_size: 2)
    pages = [
      { "jobs" => [ api_job("a"), api_job("b") ] }.to_json,
      "<html>not json</html>"
    ]
    fetcher = FakeFetcher.new(pages)
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 2, candidates.size, "rows from the good page must survive"
    end
  end

  test "records scan metrics that separate rows offered from candidates built" do
    source_scan = build_source_scan(max_pages: 2, page_size: 2)
    # Two API rows survive the pre-filter, two do not, and one is a duplicate.
    duplicate = api_job("a")
    pages = [
      { "jobs" => [ api_job("a"), rejected_job("junior") ] }.to_json,
      { "jobs" => [ duplicate, api_job("b") ] }.to_json
    ]
    adapter = JobDiscovery::Adapters::ArtificialintelligencejobsApiAdapter.new(fetcher: FakeFetcher.new(pages))

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)
      metadata = source_scan.reload.metadata

      assert_equal 2, candidates.size
      assert_equal 4, metadata["api_rows_seen"], "rows the API offered"
      assert_equal 3, metadata["candidates_built"], "rows that survived the pre-filter"
      assert_equal 2, metadata["candidates_after_dedupe"]
      assert_equal 0, metadata["detail_budget_remaining"]
    end
  end

  private
    def build_source_scan(max_pages: 1, page_size: 50, max_detail_pages: 0)
      source = JobSource.create!(
        name: "AI Jobs Test",
        slug: "artificial-intelligence-jobs-test",
        host: "artificialintelligencejobs.co",
        base_url: "https://artificialintelligencejobs.co/remote-ai-jobs",
        source_kind: :aggregator,
        adapter_key: "artificialintelligencejobs_api",
        supports_backfill: true,
        scan_window_days: 20,
        settings: { "remote_only" => true, "max_pages" => max_pages, "page_size" => page_size, "max_detail_pages" => max_detail_pages }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end

    def api_job(suffix)
      {
        "title" => "Senior Ruby on Rails Engineer #{suffix}",
        "company" => "Acme AI",
        "location" => "Remote",
        "remote" => true,
        "posted" => "2026-08-24",
        "url" => "https://artificialintelligencejobs.co/jobs/acme-#{suffix}",
        "apply_url" => "https://jobs.ashbyhq.com/acme/#{suffix}"
      }
    end

    def rejected_job(suffix)
      api_job(suffix).merge("title" => "Junior Ruby Developer #{suffix}")
    end
end
