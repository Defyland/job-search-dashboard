require "test_helper"

class JobDiscovery::Adapters::GreenhouseBoardsApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5)
      @responses.fetch(url)
    end
  end

  test "discovers board tokens from persisted greenhouse jobs and extracts strong matches" do
    source = JobSource.create!(
      name: "Greenhouse Test",
      slug: "greenhouse-test",
      host: "job-boards.greenhouse.io",
      base_url: "https://job-boards.greenhouse.io",
      source_kind: :ats,
      adapter_key: "greenhouse_boards_api",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {}
    )
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Seed Greenhouse Job",
      company_name: "Fueled",
      apply_url: "https://job-boards.greenhouse.io/fueledcareers/jobs/5134378008",
      canonical_url: "https://job-boards.greenhouse.io/fueledcareers/jobs/5134378008",
      source_url: "https://job-boards.greenhouse.io/fueledcareers/jobs/5134378008",
      fingerprint: "seed::greenhouse::fueled",
      remote_text: "Remote",
      location_text: "Brazil"
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    recent_timestamp = 2.days.ago.change(usec: 0).iso8601

    response_body = {
      jobs: [
        {
          "id" => 5_134_378_008,
          "title" => "Senior React Native Engineer",
          "absolute_url" => "https://job-boards.greenhouse.io/fueledcareers/jobs/5134378008",
          "updated_at" => recent_timestamp,
          "first_published" => recent_timestamp,
          "company_name" => "Fueled",
          "location" => { "name" => "Remote, Brazil" },
          "content" => "React Native role for Brazil"
        },
        {
          "id" => 123,
          "title" => "Senior Data Scientist",
          "absolute_url" => "https://job-boards.greenhouse.io/fueledcareers/jobs/123",
          "updated_at" => recent_timestamp,
          "first_published" => recent_timestamp,
          "company_name" => "Fueled",
          "location" => { "name" => "Remote, Brazil" },
          "content" => "Python and ML role"
        }
      ]
    }.to_json

    adapter = JobDiscovery::Adapters::GreenhouseBoardsApiAdapter.new(
      fetcher: FakeFetcher.new("https://boards-api.greenhouse.io/v1/boards/fueledcareers/jobs?content=true" => response_body)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Fueled", candidates.first[:company_name]
    assert_equal "5134378008", candidates.first[:external_job_id]
  end
end
