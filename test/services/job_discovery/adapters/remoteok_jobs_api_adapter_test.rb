require "test_helper"

class JobDiscovery::Adapters::RemoteokJobsApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(response)
      @response = response
    end

    def call(url, limit: 5)
      @response
    end
  end

  test "scans the remoteok feed and extracts remote senior ruby matches" do
    source = job_sources(:workable)
    source.update!(adapter_key: "remoteok_jobs_api", supports_backfill: true, scan_window_days: 20, settings: {})
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    response_body = [
      { "last_updated" => 1_800_000_000, "legal" => "API terms" },
      {
        "id" => "senior-ruby-on-rails",
        "slug" => "senior-ruby-on-rails-remote",
        "position" => "Senior Ruby on Rails Developer",
        "company" => "Lighthouse",
        "url" => "https://remoteok.com/remote-jobs/senior-ruby-on-rails-developer",
        "apply_url" => "https://apply.example.com/senior-ruby-on-rails",
        "date" => 2.days.ago.change(usec: 0).iso8601,
        "epoch" => 2.days.ago.to_i,
        "location" => "worldwide",
        "tags" => %w[ruby rails remote],
        "salary_min" => 120_000,
        "salary_max" => 160_000
      },
      {
        "id" => "product-designer",
        "position" => "Product Designer",
        "company" => "Lighthouse",
        "url" => "https://remoteok.com/remote-jobs/product-designer",
        "date" => 1.day.ago.change(usec: 0).iso8601,
        "location" => "worldwide",
        "tags" => %w[design]
      }
    ].to_json

    adapter = JobDiscovery::Adapters::RemoteokJobsApiAdapter.new(
      fetcher: FakeFetcher.new(response_body)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Lighthouse", candidates.first[:company_name]
    assert_equal "senior-ruby-on-rails", candidates.first[:external_job_id]
    assert_equal "https://apply.example.com/senior-ruby-on-rails", candidates.first[:apply_url]
    assert_includes candidates.first[:remote_text], "Remote"
  end

  test "skips old remoteok jobs outside the requested window" do
    source = job_sources(:workable)
    source.update!(adapter_key: "remoteok_jobs_api", supports_backfill: true, scan_window_days: 7, settings: {})
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "7d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    response_body = [
      {
        "id" => "old",
        "position" => "Senior Ruby on Rails Developer",
        "company" => "OldCo",
        "url" => "https://remoteok.com/remote-jobs/old",
        "date" => 30.days.ago.change(usec: 0).iso8601,
        "location" => "worldwide",
        "tags" => %w[ruby]
      }
    ].to_json

    adapter = JobDiscovery::Adapters::RemoteokJobsApiAdapter.new(
      fetcher: FakeFetcher.new(response_body)
    )

    assert_empty adapter.scan(source_scan:, window_days: 7)
  end
end
