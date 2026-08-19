require "test_helper"

class JobDiscovery::Adapters::RailsJobsRssAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "discovers recent remote Rails roles from the official RSS feed" do
    source_scan = build_source_scan
    rss = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Senior Ruby on Rails Engineer at Acme</title>
            <description>&lt;p&gt;Fully remote role for Latin America using Ruby on Rails and React.&lt;/p&gt;&lt;p&gt;&lt;a href="https://acme.example/apply"&gt;Apply here&lt;/a&gt;&lt;/p&gt;</description>
            <pubDate>Tue, 18 Aug 2026 12:00:00 +0000</pubDate>
            <link>https://jobs.rubyonrails.org/jobs/39438-senior-ruby-on-rails-engineer-acme</link>
            <guid>rails-job-39438</guid>
          </item>
          <item>
            <title>Junior Rails Engineer at OldCo</title>
            <description>&lt;p&gt;Remote Ruby on Rails role.&lt;/p&gt;</description>
            <pubDate>Tue, 18 Aug 2026 12:00:00 +0000</pubDate>
            <link>https://jobs.rubyonrails.org/jobs/39439-junior-rails-engineer-oldco</link>
          </item>
        </channel>
      </rss>
    XML
    adapter = JobDiscovery::Adapters::RailsJobsRssAdapter.new(
      fetcher: FakeFetcher.new("https://jobs.rubyonrails.org/jobs.rss" => rss)
    )

    travel_to Time.zone.parse("2026-08-19 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      assert_equal "strong", candidates.first[:classification]
      assert_equal "Acme", candidates.first[:company_name]
      assert_equal "39438", candidates.first[:external_job_id]
      assert_equal "https://acme.example/apply", candidates.first[:apply_url]
      assert_equal "Fully remote", candidates.first[:remote_text]
    end
  end

  private
    def build_source_scan
      source = JobSource.create!(
        name: "Rails Job Board Test",
        slug: "rails-job-board-test",
        host: "jobs.rubyonrails.org",
        base_url: "https://jobs.rubyonrails.org",
        source_kind: :platform,
        adapter_key: "rails_jobs_rss",
        supports_backfill: true,
        scan_window_days: 20,
        settings: { "feed_url" => "https://jobs.rubyonrails.org/jobs.rss" }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end
end
