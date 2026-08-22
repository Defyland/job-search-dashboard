require "test_helper"

class JobDiscovery::Adapters::WeworkremotelyRssAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "splits the company prefix, keeps recent matches, and drops expired postings" do
    source_scan = build_source_scan
    feed_url = "https://weworkremotely.com/categories/remote-programming-jobs.rss"
    feed = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"><channel>
        <item>
          <title>Acme: Senior Ruby on Rails Engineer</title>
          <region>Anywhere in the World</region>
          <country></country>
          <state></state>
          <skills>Ruby, Rails</skills>
          <category>Back-End Programming</category>
          <type>Full-Time</type>
          <description>&lt;p&gt;Fully remote Ruby on Rails role.&lt;/p&gt;</description>
          <pubDate>Tue, 18 Aug 2026 12:00:00 +0000</pubDate>
          <expires_at>Thu, 17 Sep 2026 12:00:00 +0000</expires_at>
          <guid>https://weworkremotely.com/remote-jobs/acme-senior-ruby-on-rails-engineer</guid>
          <link>https://weworkremotely.com/remote-jobs/acme-senior-ruby-on-rails-engineer</link>
        </item>
        <item>
          <title>OldCo: Senior Ruby Engineer</title>
          <region>Anywhere in the World</region>
          <category>Back-End Programming</category>
          <type>Full-Time</type>
          <description>&lt;p&gt;Remote Ruby role.&lt;/p&gt;</description>
          <pubDate>Tue, 18 Aug 2026 12:00:00 +0000</pubDate>
          <expires_at>Mon, 18 Aug 2026 13:00:00 +0000</expires_at>
          <link>https://weworkremotely.com/remote-jobs/oldco-senior-ruby-engineer</link>
        </item>
        <item>
          <title>Ignored: Junior Ruby Developer</title>
          <region>Anywhere in the World</region>
          <description>&lt;p&gt;Remote junior role.&lt;/p&gt;</description>
          <pubDate>Tue, 18 Aug 2026 12:00:00 +0000</pubDate>
          <link>https://weworkremotely.com/remote-jobs/ignored-junior-ruby-developer</link>
        </item>
      </channel></rss>
    XML
    adapter = JobDiscovery::Adapters::WeworkremotelyRssAdapter.new(
      fetcher: FakeFetcher.new(feed_url => feed)
    )

    travel_to Time.zone.parse("2026-08-19 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      candidate = candidates.first
      assert_equal "strong", candidate[:classification]
      assert_equal "Senior Ruby on Rails Engineer", candidate[:title]
      assert_equal "Acme", candidate[:company_name]
      assert_equal "Remote | Anywhere in the World", candidate[:remote_text]
      assert_equal "acme-senior-ruby-on-rails-engineer", candidate[:external_job_id]
      assert_equal "https://weworkremotely.com/remote-jobs/acme-senior-ruby-on-rails-engineer", candidate[:apply_url]
      assert_equal %w[Ruby Rails], candidate.dig(:payload, :skills)
      assert_equal 1, source_scan.reload.pages_scanned
    end
  end

  test "deduplicates the same posting across configured category feeds" do
    shared_feed_urls = [
      "https://weworkremotely.com/categories/remote-programming-jobs.rss",
      "https://weworkremotely.com/categories/remote-full-stack-programming-jobs.rss"
    ]
    source_scan = build_source_scan(feed_urls: shared_feed_urls)
    feed = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"><channel>
        <item>
          <title>Acme: Senior Ruby on Rails Engineer</title>
          <region>Anywhere in the World</region>
          <description>&lt;p&gt;Fully remote Ruby on Rails role.&lt;/p&gt;</description>
          <pubDate>Tue, 18 Aug 2026 12:00:00 +0000</pubDate>
          <link>https://weworkremotely.com/remote-jobs/acme-senior-ruby-on-rails-engineer?utm_source=rss</link>
        </item>
      </channel></rss>
    XML
    adapter = JobDiscovery::Adapters::WeworkremotelyRssAdapter.new(
      fetcher: FakeFetcher.new(shared_feed_urls.index_with { feed })
    )

    travel_to Time.zone.parse("2026-08-19 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      assert_equal "https://weworkremotely.com/remote-jobs/acme-senior-ruby-on-rails-engineer", candidates.first[:canonical_url]
      assert_equal 2, source_scan.reload.pages_scanned
    end
  end

  private
    def build_source_scan(feed_urls: [ "https://weworkremotely.com/categories/remote-programming-jobs.rss" ])
      source = JobSource.create!(
        name: "We Work Remotely Test",
        slug: "weworkremotely-test",
        host: "weworkremotely.com",
        base_url: "https://weworkremotely.com",
        source_kind: :platform,
        adapter_key: "weworkremotely_rss",
        supports_backfill: true,
        scan_window_days: 20,
        settings: { "feed_urls" => feed_urls }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end
end
