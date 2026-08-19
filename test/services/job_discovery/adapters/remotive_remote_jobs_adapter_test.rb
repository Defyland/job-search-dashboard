require "test_helper"

class JobDiscovery::Adapters::RemotiveRemoteJobsAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(response)
      @response = response
    end

    def call(url, limit: 5)
      @response
    end
  end

  test "scans the remotive feed and extracts remote senior ruby matches" do
    source = job_sources(:workable)
    source.update!(adapter_key: "remotive_remote_jobs", supports_backfill: true, scan_window_days: 20, settings: {})
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    response_body = {
      "job-count" => 2,
      "jobs" => [
        {
          "id" => 2091093,
          "url" => "https://remotive.com/remote-jobs/backend/senior-ruby-on-rails-2091093",
          "title" => "Senior Ruby on Rails Developer",
          "company_name" => "Mercor",
          "category" => "Software Development",
          "tags" => %w[ruby rails],
          "job_type" => "full_time",
          "publication_date" => 2.days.ago.change(usec: 0).iso8601,
          "candidate_required_location" => "Worldwide",
          "salary" => "USD 120k",
          "description" => "<p>Remote Ruby on Rails role.</p>"
        },
        {
          "id" => 2091094,
          "url" => "https://remotive.com/remote-jobs/design/product-designer-2091094",
          "title" => "Product Designer",
          "company_name" => "Mercor",
          "category" => "Design",
          "tags" => %w[design],
          "job_type" => "full_time",
          "publication_date" => 1.day.ago.change(usec: 0).iso8601,
          "candidate_required_location" => "Worldwide",
          "description" => "<p>Design role.</p>"
        }
      ]
    }.to_json

    adapter = JobDiscovery::Adapters::RemotiveRemoteJobsAdapter.new(
      fetcher: FakeFetcher.new(response_body)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Mercor", candidates.first[:company_name]
    assert_equal "2091093", candidates.first[:external_job_id]
    assert_equal "https://remotive.com/remote-jobs/backend/senior-ruby-on-rails-2091093", candidates.first[:apply_url]
  end
end
