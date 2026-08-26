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

    def call(url, limit: 5, headers: {})
      if url.include?("/jobs/")
        @detail_urls << url
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
end
