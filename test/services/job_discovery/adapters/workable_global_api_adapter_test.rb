require "test_helper"

class JobDiscovery::Adapters::WorkableGlobalApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5)
      @responses.fetch(url)
    end
  end

  test "scans workable api pages and extracts remote senior ruby matches" do
    source = job_sources(:workable)
    source.update!(adapter_key: "workable_global_api", supports_backfill: true, scan_window_days: 20, settings: { "max_pages" => 1 })
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    recent_timestamp = 2.days.ago.change(usec: 0).iso8601

    response_body = {
      jobs: [
        {
          "id" => "vFiUCegceZETVwRh5nAx32",
          "title" => "Remote Senior Ruby on Rails Developer",
          "state" => "published",
          "description" => "<p>Remote role for Ruby on Rails in Brazil</p>",
          "employmentType" => "Full-time",
          "updated" => recent_timestamp,
          "created" => recent_timestamp,
          "url" => "https://jobs.workable.com/view/vFiUCegceZETVwRh5nAx32/remote-senior-ruby-on-rails-developer",
          "workplace" => "remote",
          "location" => { "city" => "São Paulo", "countryName" => "Brazil" },
          "company" => { "title" => "Sur", "url" => "https://apply.workable.com/sur/" }
        },
        {
          "id" => "other",
          "title" => "Product Designer",
          "state" => "published",
          "description" => "<p>Remote</p>",
          "updated" => recent_timestamp,
          "created" => recent_timestamp,
          "url" => "https://jobs.workable.com/view/other/product-designer",
          "workplace" => "remote",
          "location" => { "countryName" => "Brazil" },
          "company" => { "title" => "Sur", "url" => "https://apply.workable.com/sur/" }
        }
      ],
      nextPageToken: nil
    }.to_json

    adapter = JobDiscovery::Adapters::WorkableGlobalApiAdapter.new(
      fetcher: FakeFetcher.new("https://jobs.workable.com/api/v1/jobs" => response_body)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Sur", candidates.first[:company_name]
    assert_equal "vFiUCegceZETVwRh5nAx32", candidates.first[:external_job_id]
  end

  test "stops on old workable jobs outside the requested window" do
    source = job_sources(:workable)
    source.update!(adapter_key: "workable_global_api", supports_backfill: true, scan_window_days: 20, settings: { "max_pages" => 1 })
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "7d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    old_job_response = {
      jobs: [
        {
          "id" => "old",
          "title" => "Remote Senior React Developer",
          "state" => "published",
          "description" => "<p>Remote React</p>",
          "updated" => "2026-05-01T10:00:00Z",
          "created" => "2026-05-01T10:00:00Z",
          "url" => "https://jobs.workable.com/view/old/remote-senior-react-developer",
          "workplace" => "remote",
          "location" => { "countryName" => "Brazil" },
          "company" => { "title" => "Old Co", "url" => "https://apply.workable.com/old/" }
        }
      ],
      nextPageToken: nil
    }.to_json

    adapter = JobDiscovery::Adapters::WorkableGlobalApiAdapter.new(
      fetcher: FakeFetcher.new("https://jobs.workable.com/api/v1/jobs" => old_job_response)
    )

    candidates = adapter.scan(source_scan:, window_days: 7)

    assert_empty candidates
  end
end
