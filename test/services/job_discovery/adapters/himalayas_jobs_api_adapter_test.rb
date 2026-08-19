require "test_helper"

class JobDiscovery::Adapters::HimalayasJobsApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(response)
      @response = response
    end

    def call(url, limit: 5)
      @response
    end
  end

  test "scans himalayas pages, falls back to the company slug, and filters by window" do
    source = job_sources(:workable)
    source.update!(adapter_key: "himalayas_jobs_api", supports_backfill: true, scan_window_days: 20, settings: { "max_pages" => 1, "results_per_page" => 50 })
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    response_body = {
      "totalCount" => 100,
      "jobs" => [
        {
          "title" => "Senior Ruby on Rails Engineer",
          "companyName" => "name",
          "companySlug" => "mercor",
          "guid" => "https://himalayas.app/companies/mercor/jobs/senior-ruby-on-rails-engineer",
          "applicationLink" => "https://himalayas.app/companies/mercor/jobs/senior-ruby-on-rails-engineer",
          "pubDate" => 2.days.ago.to_i,
          "locationRestrictions" => [ "Worldwide" ],
          "minSalary" => 100_000,
          "maxSalary" => 140_000,
          "currency" => "USD",
          "categories" => %w[engineering backend]
        },
        {
          "title" => "Ruby on Rails Architect",
          "companyName" => "name",
          "companySlug" => "oldco",
          "guid" => "https://himalayas.app/companies/oldco/jobs/ruby-on-rails-architect",
          "applicationLink" => "https://himalayas.app/companies/oldco/jobs/ruby-on-rails-architect",
          "pubDate" => 40.days.ago.to_i,
          "locationRestrictions" => [ "Worldwide" ]
        }
      ]
    }.to_json

    adapter = JobDiscovery::Adapters::HimalayasJobsApiAdapter.new(
      fetcher: FakeFetcher.new(response_body)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Mercor", candidates.first[:company_name]
    assert_equal "https://himalayas.app/companies/mercor/jobs/senior-ruby-on-rails-engineer", candidates.first[:external_job_id]
    assert_includes candidates.first[:remote_text], "Remote"
  end
end
