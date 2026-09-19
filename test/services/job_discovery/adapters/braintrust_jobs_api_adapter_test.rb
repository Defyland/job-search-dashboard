require "test_helper"

class JobDiscovery::Adapters::BraintrustJobsApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :urls, :detail_urls

    def initialize(pages, detail_body: nil)
      @pages = pages
      @detail_body = detail_body
      @urls = []
      @detail_urls = []
    end

    def call(url, limit: 5, headers: {}, allowed_hosts: nil)
      if url.match?(%r{/api/jobs/\d+})
        @detail_urls << url
        raise JobDiscovery::Fetcher::RequestError.new("detail unavailable", code: 500) if @detail_body == :raise

        return @detail_body.to_s
      end

      @urls << url
      @pages.shift || { results: [], count: 0 }.to_json
    end
  end

  test "builds candidates from the public API and enriches with bounded detail fetches" do
    source_scan = build_source_scan(max_detail_pages: 1)
    page = {
      "count" => 2,
      "results" => [
        api_job("a"),
        {
          "id" => 200,
          "title" => "Senior Ruby on Rails Developer",
          "employer" => { "name" => "Acme Freelance" },
          "created" => "2026-08-24T10:00:00Z",
          "locations" => [ { "location" => "Mexico", "custom_location" => nil } ],
          "contract_type" => "long",
          "job_type" => "freelance",
          "payment_type" => "hourly",
          "budget_minimum_usd" => 55,
          "budget_maximum_usd" => 65,
          "role" => { "name" => "Engineering" },
          "job_skills" => [ { "skill" => { "name" => "Ruby" } } ]
        }
      ]
    }.to_json
    detail = {
      "id" => 1,
      "title" => "Senior Ruby on Rails Engineer a",
      "description" => "<p>Build and maintain Rails services for a remote team.</p>",
      "published_at" => "2026-08-24T10:00:00Z",
      "is_open" => true,
      "job_status" => "open",
      "experience_level" => "five_ten_years",
      "timezones" => [ { "timezone" => "CST/CDT" } ]
    }.to_json
    fetcher = FakeFetcher.new([ page ], detail_body: detail)
    adapter = JobDiscovery::Adapters::BraintrustJobsApiAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 2, candidates.size
      candidate = candidates.first
      assert_equal "strong", candidate[:classification], candidate[:reason]
      assert_equal "Senior Ruby on Rails Engineer a", candidate[:title]
      assert_equal "https://app.usebraintrust.com/jobs/1", candidate[:canonical_url]
      assert_includes candidate[:description], "Build and maintain Rails"
      assert_equal 1, fetcher.detail_urls.size, "only accepted titles earn a detail request"
    end
  end

  test "marks a filled or closed job as expired from the detail payload" do
    source_scan = build_source_scan(max_detail_pages: 2)
    page = { "count" => 1, "results" => [ api_job("closed") ] }.to_json
    detail = {
      "id" => 1,
      "description" => "<p>Ruby on Rails</p>",
      "published_at" => "2026-08-24T10:00:00Z",
      "is_open" => false,
      "job_status" => "filled"
    }.to_json

    candidates = nil
    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = JobDiscovery::Adapters::BraintrustJobsApiAdapter.new(
        fetcher: FakeFetcher.new([ page ], detail_body: detail)
      ).scan(source_scan:, window_days: 20)
    end

    assert_equal 1, candidates.size
    assert_equal "expired", candidates.first[:classification]
  end

  test "paginates through the advertised pages and stops on count" do
    source_scan = build_source_scan(max_pages: 4, page_size: 2)
    fresh = ->(suffix) { api_job(suffix).merge("title" => "Senior Ruby on Rails Engineer #{suffix}") }
    pages = [
      { "count" => 4, "results" => [ fresh.call("a"), fresh.call("b") ] }.to_json,
      { "count" => 4, "results" => [ fresh.call("c"), fresh.call("d") ] }.to_json
    ]
    fetcher = FakeFetcher.new(pages)

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = JobDiscovery::Adapters::BraintrustJobsApiAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

      assert_equal 4, candidates.size
      assert_equal 2, fetcher.urls.size
      assert_includes fetcher.urls.first, "page=1"
      assert_includes fetcher.urls.last, "page=2"
    end
  end

  test "max_detail_pages zero disables detail fetching" do
    source_scan = build_source_scan(max_detail_pages: 0)
    fetcher = FakeFetcher.new([ { "count" => 1, "results" => [ api_job("a") ] }.to_json ], detail_body: "{}")

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = JobDiscovery::Adapters::BraintrustJobsApiAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      assert_empty fetcher.detail_urls, "a configured 0 must not be coerced to 1"
    end
  end

  test "stale rows are dropped on the list before any detail fetch" do
    source_scan = build_source_scan(max_detail_pages: 5)
    stale = api_job("stale").merge("created" => 60.days.ago.iso8601)
    fetcher = FakeFetcher.new([ { "count" => 1, "results" => [ stale ] }.to_json ], detail_body: "{}")

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = JobDiscovery::Adapters::BraintrustJobsApiAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

      assert_empty candidates
      assert_empty fetcher.detail_urls
    end
  end

  test "records scan metrics separating rows offered from candidates built" do
    source_scan = build_source_scan(max_pages: 2, page_size: 2, max_detail_pages: 0)
    duplicate = api_job("a")
    pages = [
      { "count" => 3, "results" => [ api_job("a"), rejected_job("junior") ] }.to_json,
      { "count" => 3, "results" => [ duplicate, api_job("b") ] }.to_json
    ]
    adapter = JobDiscovery::Adapters::BraintrustJobsApiAdapter.new(fetcher: FakeFetcher.new(pages))

    travel_to Time.zone.parse("2026-08-26 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)
      metadata = source_scan.reload.metadata

      assert_equal 2, candidates.size
      assert_equal 4, metadata["api_rows_seen"]
      assert_equal 3, metadata["candidates_built"]
      assert_equal 2, metadata["candidates_after_dedupe"]
    end
  end

  private
    def build_source_scan(max_pages: 1, page_size: 50, max_detail_pages: 0)
      source = JobSource.create!(
        name: "Braintrust Test",
        slug: "braintrust-test",
        host: "app.usebraintrust.com",
        base_url: "https://app.usebraintrust.com",
        source_kind: :platform,
        adapter_key: "braintrust_jobs_api",
        supports_backfill: true,
        scan_window_days: 20,
        settings: { "max_pages" => max_pages, "page_size" => page_size, "max_detail_pages" => max_detail_pages }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end

    def api_job(suffix)
      {
        "id" => { "a" => 1, "b" => 2, "c" => 3, "d" => 4, "stale" => 5, "closed" => 6 }.fetch(suffix.to_s, suffix.to_s.bytes.sum + 1),
        "title" => "Senior Ruby on Rails Engineer #{suffix}",
        "employer" => { "name" => "Acme Freelance" },
        "created" => "2026-08-24T10:00:00Z",
        "locations" => [ { "location" => "Mexico", "custom_location" => "south_america" } ],
        "contract_type" => "long",
        "job_type" => "freelance",
        "payment_type" => "hourly",
        "budget_minimum_usd" => 55,
        "budget_maximum_usd" => 65,
        "role" => { "name" => "Engineering" },
        "job_skills" => [ { "skill" => { "name" => "Ruby" } } ]
      }
    end

    def rejected_job(suffix)
      api_job(suffix).merge("title" => "Junior Ruby Developer #{suffix}")
    end
end
