require "test_helper"

class JobDiscovery::Adapters::RemoteyeahRssAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "discovers the configured job page and recent matches from the public RSS feed" do
    source_scan = build_source_scan
    seed_url = "https://remoteyeah.com/jobs/remote-lead-ruby-on-rails-software-engineer-alex-staff-agency-4"
    page = <<~HTML
      <html><head>
        <script type="application/ld+json">
          {
            "@type": "JobPosting",
            "title": "Lead Ruby on Rails Software Engineer",
            "description": "<p>Lead a Ruby on Rails platform.</p>",
            "datePosted": "2026-08-05T00:44:10+00:00",
            "validThrough": "2026-11-05T00:44:10+00:00",
            "jobLocationType": "TELECOMMUTE",
            "applicantLocationRequirements": [{"name": "Portugal"}],
            "employmentType": ["CONTRACTOR"],
            "skills": "Ruby, Ruby on Rails",
            "hiringOrganization": {"name": "Alex Staff Agency"}
          }
        </script>
      </head></html>
    HTML
    rss = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"><channel>
        <item>
          <title>Remote Senior Full Stack Developer (Ruby on Rails, React) at Miratech</title>
          <company>Miratech</company>
          <description><![CDATA[<p>Build a Ruby on Rails and React platform.</p>]]></description>
          <category>Full-Stack Engineer</category>
          <tags>Ruby, Ruby on Rails, React, Senior</tags>
          <location>Worldwide</location>
          <pubDate>2026-08-18T12:31:23+00:00</pubDate>
          <guid isPermaLink="false">senior-full-stack-miratech</guid>
          <link>https://remoteyeah.com/jobs/remote-senior-full-stack-developer-miratech?utm_source=rss&amp;ref=rss</link>
        </item>
        <item>
          <title>Remote Junior Ruby Developer at Example</title>
          <pubDate>2026-08-18T12:31:23+00:00</pubDate>
          <link>https://remoteyeah.com/jobs/remote-junior-ruby-developer-example</link>
        </item>
      </channel></rss>
    XML
    profile = JobDiscovery::Policy.default_profile
    profile.seniority_terms = profile.seniority_terms + [ "lead" ]
    adapter = JobDiscovery::Adapters::RemoteyeahRssAdapter.new(
      fetcher: FakeFetcher.new(seed_url => page, "https://remoteyeah.com/rss.xml" => rss),
      policy: JobDiscovery::Policy.new(search_profile: profile)
    )

    travel_to Time.zone.parse("2026-08-19 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 2, candidates.size

      seeded = candidates.find { |candidate| candidate[:external_job_id].end_with?("agency-4") }
      assert_equal "strong", seeded[:classification]
      assert_equal "Alex Staff Agency", seeded[:company_name]
      assert_equal "Portugal", seeded[:location_text]
      assert_equal seed_url, seeded[:canonical_url]

      feed_candidate = candidates.find { |candidate| candidate[:external_job_id] == "senior-full-stack-miratech" }
      assert_equal "Miratech", feed_candidate[:company_name]
      assert_equal "Remote | Worldwide", feed_candidate[:remote_text]
      assert_equal "https://remoteyeah.com/jobs/remote-senior-full-stack-developer-miratech", feed_candidate[:canonical_url]
    end
  end

  private
    def build_source_scan
      source = JobSource.create!(
        name: "RemoteYeah",
        slug: "remoteyeah-test",
        host: "remoteyeah.com",
        base_url: "https://remoteyeah.com",
        source_kind: :platform,
        adapter_key: "remoteyeah_rss",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          "feed_url" => "https://remoteyeah.com/rss.xml",
          "seed_urls" => [
            "https://remoteyeah.com/jobs/remote-lead-ruby-on-rails-software-engineer-alex-staff-agency-4?utm_source=linkedin"
          ]
        }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d")
      search_run.source_scans.create!(job_source: source, status: :running)
    end
end
