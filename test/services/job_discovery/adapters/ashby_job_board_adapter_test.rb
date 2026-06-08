require "test_helper"

class JobDiscovery::Adapters::AshbyJobBoardAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5)
      @responses.fetch(url)
    end
  end

  test "discovers board slugs from persisted ashby jobs and extracts strong matches" do
    source = JobSource.create!(
      name: "Ashby Test",
      slug: "ashby-test",
      host: "jobs.ashbyhq.com",
      base_url: "https://jobs.ashbyhq.com",
      source_kind: :ats,
      adapter_key: "ashby_job_board",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {}
    )
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Seed Ashby Job",
      company_name: "Ruby Labs",
      apply_url: "https://jobs.ashbyhq.com/ruby-labs/5fc64202-b0a7-4cb7-b7ff-07fc63fd5325",
      canonical_url: "https://jobs.ashbyhq.com/ruby-labs/5fc64202-b0a7-4cb7-b7ff-07fc63fd5325",
      source_url: "https://jobs.ashbyhq.com/ruby-labs/5fc64202-b0a7-4cb7-b7ff-07fc63fd5325",
      fingerprint: "seed::ashby::ruby-labs",
      remote_text: "Remote",
      location_text: "Brazil"
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    app_data = {
      organization: { name: "Ruby Labs" },
      jobBoard: {
        jobPostings: [
          {
            id: "5fc64202-b0a7-4cb7-b7ff-07fc63fd5325",
            title: "Senior React Native Developer",
            updatedAt: "2026-06-02T20:44:31.423Z",
            publishedDate: "2026-06-02",
            workplaceType: "Remote",
            locationName: "Brazil",
            teamName: "Engineering",
            departmentName: "Engineering",
            secondaryLocations: [ { locationName: "Brazil" } ]
          },
          {
            id: "other",
            title: "Senior Growth Manager",
            updatedAt: "2026-06-02T20:44:31.423Z",
            publishedDate: "2026-06-02",
            workplaceType: "Remote",
            locationName: "Europe"
          }
        ]
      }
    }.to_json

    board_html = <<~HTML
      <html><body>
        <script>
          window.__appData = #{app_data};
          fetch("https://cdn.ashbyprd.com/example");
        </script>
      </body></html>
    HTML

    adapter = JobDiscovery::Adapters::AshbyJobBoardAdapter.new(
      fetcher: FakeFetcher.new("https://jobs.ashbyhq.com/ruby-labs" => board_html)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Ruby Labs", candidates.first[:company_name]
    assert_equal "5fc64202-b0a7-4cb7-b7ff-07fc63fd5325", candidates.first[:external_job_id]
  end
end
