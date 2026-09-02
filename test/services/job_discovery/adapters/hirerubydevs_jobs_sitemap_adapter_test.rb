require "test_helper"

class JobDiscovery::Adapters::HirerubydevsJobsSitemapAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def call(url, limit: 5, headers: {}, allowed_hosts: nil)
      @requests << [ url, allowed_hosts ]
      @responses.fetch(url)
    end
  end

  SITEMAP_URL = "https://hirerubydevs.com/sitemap.xml".freeze

  def build_source_scan(settings = {})
    source = JobSource.create!(
      name: "HireRubyDevs Test",
      slug: "hirerubydevs-test",
      host: "hirerubydevs.com",
      base_url: "https://hirerubydevs.com/jobs",
      source_kind: :platform,
      adapter_key: "hirerubydevs_jobs_sitemap",
      supports_backfill: true,
      scan_window_days: 20,
      settings:
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
  end

  def sitemap(entries)
    rows = entries.map { |url, lastmod| "<url><loc>#{url}</loc><lastmod>#{lastmod}</lastmod></url>" }.join
    %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{rows}</urlset>)
  end

  def job_page(title:, url:, company: "Cloudflare", date_posted: 2.days.ago.iso8601, valid_through: 30.days.from_now.iso8601, skills: "rails, ruby", locality: "Remote")
    posting = {
      "@context" => "https://schema.org",
      "@type" => "JobPosting",
      "title" => title,
      "description" => "<p>Build and maintain Rails services.</p>",
      "datePosted" => date_posted,
      "validThrough" => valid_through,
      "skills" => skills,
      "identifier" => { "@type" => "PropertyValue", "name" => "HireRubyDevs", "value" => "1443" },
      "hiringOrganization" => { "@type" => "Organization", "name" => company, "sameAs" => "https://cloudflare.com" },
      "url" => url,
      "jobLocation" => { "@type" => "Place", "address" => { "@type" => "PostalAddress", "addressLocality" => locality } }
    }
    %(<html><head><script type="application/ld+json">#{posting.to_json}</script></head><body></body></html>)
  end

  test "builds candidates from the sitemap and the JobPosting block" do
    url = "https://hirerubydevs.com/jobs/senior-ruby-engineer-cloudflare"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      SITEMAP_URL => sitemap([ [ url, 1.day.ago.iso8601 ] ]),
      url => job_page(title: "Senior Ruby on Rails Engineer", url:)
    )

    candidates = JobDiscovery::Adapters::HirerubydevsJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    candidate = candidates.first
    assert_equal "Senior Ruby on Rails Engineer", candidate[:title]
    assert_equal "Cloudflare", candidate[:company_name]
    assert_equal url, candidate[:canonical_url]
    assert_equal "1443", candidate[:external_job_id]
    assert_equal "Remote", candidate[:remote_text]
    # The board's own skills field must reach the policy alongside the prose.
    assert_includes candidate[:description], "rails, ruby"
    assert_equal 1, source_scan.reload.metadata["candidates_built"]
  end

  test "never requests the robots-disallowed apply route and pins every hop" do
    url = "https://hirerubydevs.com/jobs/senior-ruby-engineer-cloudflare"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      SITEMAP_URL => sitemap([ [ url, 1.day.ago.iso8601 ] ]),
      url => job_page(title: "Senior Ruby on Rails Engineer", url:)
    )

    candidates = JobDiscovery::Adapters::HirerubydevsJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal url, candidates.first[:apply_url]
    assert fetcher.requests.none? { |requested, _| requested.end_with?("/apply", "/website") }
    assert fetcher.requests.all? { |_, allowed_hosts| allowed_hosts == [ "hirerubydevs.com" ] }
  end

  test "ignores sitemap rows outside the vacancy path or outside the window" do
    fresh = "https://hirerubydevs.com/jobs/senior-ruby-engineer-acme"
    stale = "https://hirerubydevs.com/jobs/senior-ruby-engineer-stale"
    apply_route = "https://hirerubydevs.com/jobs/senior-ruby-engineer-acme/apply"
    guide = "https://hirerubydevs.com/learn/ruby"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      SITEMAP_URL => sitemap([
        [ fresh, 1.day.ago.iso8601 ],
        [ stale, 90.days.ago.iso8601 ],
        [ apply_route, 1.day.ago.iso8601 ],
        [ guide, 1.day.ago.iso8601 ]
      ]),
      fresh => job_page(title: "Senior Ruby on Rails Engineer", url: fresh)
    )

    candidates = JobDiscovery::Adapters::HirerubydevsJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal [ fresh ], candidates.map { |candidate| candidate[:canonical_url] }
    requested = fetcher.requests.map(&:first)
    assert_not_includes requested, stale
    assert_not_includes requested, apply_route
    assert_not_includes requested, guide
    assert_equal 1, source_scan.reload.metadata["sitemap_urls_seen"]
  end

  test "marks a genuinely expired posting instead of dropping it silently" do
    url = "https://hirerubydevs.com/jobs/senior-ruby-engineer-expired"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      SITEMAP_URL => sitemap([ [ url, 1.day.ago.iso8601 ] ]),
      url => job_page(title: "Senior Ruby on Rails Engineer", url:, date_posted: 10.days.ago.iso8601, valid_through: 2.days.ago.iso8601)
    )

    candidates = JobDiscovery::Adapters::HirerubydevsJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal "expired", candidates.first[:classification]
  end

  test "ignores a validThrough that predates the posting date" do
    url = "https://hirerubydevs.com/jobs/senior-ruby-engineer-republished"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      SITEMAP_URL => sitemap([ [ url, 1.hour.ago.iso8601 ] ]),
      # Observed live: a freshly republished vacancy keeping a stale validThrough.
      url => job_page(title: "Senior Ruby on Rails Engineer", url:, date_posted: 1.hour.ago.iso8601, valid_through: 20.days.ago.iso8601)
    )

    candidates = JobDiscovery::Adapters::HirerubydevsJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_not_equal "expired", candidates.first[:classification]
  end

  test "honours the configured max_jobs budget" do
    source_scan = build_source_scan("max_jobs" => 2)
    entries = (1..5).map { |index| [ "https://hirerubydevs.com/jobs/senior-ruby-engineer-#{index}", index.hours.ago.iso8601 ] }
    responses = { SITEMAP_URL => sitemap(entries) }
    entries.each { |url, _| responses[url] = job_page(title: "Senior Ruby on Rails Engineer", url:) }

    fetcher = FakeFetcher.new(responses)
    candidates = JobDiscovery::Adapters::HirerubydevsJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 2, candidates.size
    # Newest first: the sitemap order must not decide which two are fetched.
    assert_equal [ entries[0][0], entries[1][0] ], candidates.map { |candidate| candidate[:canonical_url] }
  end
end
