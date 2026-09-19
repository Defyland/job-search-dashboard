require "test_helper"

class JobDiscovery::Adapters::TalentlyftBoardSitemapAdapterTest < ActiveSupport::TestCase
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

  BOARD_URL = "https://allied-global-its.talentlyft.com".freeze
  SITEMAP_URL = "#{BOARD_URL}/sitemap.xml".freeze

  def build_source_scan(settings = {})
    source = JobSource.create!(
      name: "Allied Global ITS Test",
      slug: "allied-global-its-test",
      host: "talentlyft.com",
      base_url: BOARD_URL,
      source_kind: :ats,
      adapter_key: "talentlyft_board_sitemap",
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

  def job_page(title:, url:, company: "Allied Technology Services", date_posted: 2.days.ago.iso8601, locality: "Guatemala", country: "GT", remote: true)
    street = remote ? "#{locality}, Guatemala (Remote)" : locality
    posting = {
      "@type" => "JobPosting",
      "title" => title,
      "description" => "<p>Build and maintain Salesforce services.</p><p>Remote LATAM role.</p>",
      "datePosted" => date_posted,
      "employmentType" => "FULL_TIME",
      "hiringOrganization" => { "@type" => "Organization", "name" => company, "sameAs" => "http://alliedits.tech" },
      "jobLocation" => {
        "@type" => "Place",
        "address" => {
          "@type" => "PostalAddress",
          "streetAddress" => street,
          "addressLocality" => locality,
          "addressRegion" => locality,
          "addressCountry" => country
        }
      }
    }
    %(<html><head><script type="application/ld+json">#{posting.to_json}</script></head><body></body></html>)
  end

  test "builds candidates from the board sitemap and the JobPosting block" do
    url = "#{BOARD_URL}/jobs/salesforce-developer-litify-experience-required-clit"
    source_scan = build_source_scan("board_urls" => [ BOARD_URL ])
    fetcher = FakeFetcher.new(
      SITEMAP_URL => sitemap([ [ url, 1.day.ago.iso8601 ] ]),
      url => job_page(title: "Senior Salesforce Developer (Litify Experience Required)", url:)
    )

    candidates = JobDiscovery::Adapters::TalentlyftBoardSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    candidate = candidates.first
    assert_equal "Senior Salesforce Developer (Litify Experience Required)", candidate[:title]
    assert_equal "Allied Technology Services", candidate[:company_name]
    assert_equal url, candidate[:canonical_url]
    assert_equal "Remote", candidate[:remote_text]
    assert_includes candidate[:location_text], "Guatemala"
    assert_includes candidate[:description], "Remote LATAM"
  end

  test "pins every request to the board host and never treats the apply form as a vacancy" do
    url = "#{BOARD_URL}/jobs/senior-software-engineer"
    apply_form = "#{url}/new"
    source_scan = build_source_scan("board_urls" => [ BOARD_URL ])
    fetcher = FakeFetcher.new(
      SITEMAP_URL => sitemap([
        [ url, 1.day.ago.iso8601 ],
        [ apply_form, 1.day.ago.iso8601 ]
      ]),
      url => job_page(title: "Senior Software Engineer", url:)
    )

    candidates = JobDiscovery::Adapters::TalentlyftBoardSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal [ url ], candidates.map { |candidate| candidate[:canonical_url] }
    assert fetcher.requests.all? { |_, allowed_hosts| allowed_hosts == [ "allied-global-its.talentlyft.com" ] }
  end

  test "ignores sitemap rows outside the window and outside the jobs path" do
    fresh = "#{BOARD_URL}/jobs/senior-ruby-engineer"
    stale = "#{BOARD_URL}/jobs/senior-ruby-engineer-stale"
    landing = "#{BOARD_URL}/allied-technology-services-page"
    source_scan = build_source_scan("board_urls" => [ BOARD_URL ])
    fetcher = FakeFetcher.new(
      SITEMAP_URL => sitemap([
        [ fresh, 1.day.ago.iso8601 ],
        [ stale, 90.days.ago.iso8601 ],
        [ landing, 1.day.ago.iso8601 ]
      ]),
      fresh => job_page(title: "Senior Ruby on Rails Engineer", url: fresh)
    )

    candidates = JobDiscovery::Adapters::TalentlyftBoardSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal [ fresh ], candidates.map { |candidate| candidate[:canonical_url] }
    requested = fetcher.requests.map(&:first)
    assert_not_includes requested, stale
    assert_not_includes requested, landing
  end

  test "honours the configured max_jobs budget" do
    source_scan = build_source_scan("board_urls" => [ BOARD_URL ], "max_jobs" => 2)
    entries = (1..4).map { |index| [ "#{BOARD_URL}/jobs/senior-ruby-engineer-#{index}", index.hours.ago.iso8601 ] }
    responses = { SITEMAP_URL => sitemap(entries) }
    entries.each { |url, _| responses[url] = job_page(title: "Senior Ruby on Rails Engineer", url:) }

    fetcher = FakeFetcher.new(responses)
    candidates = JobDiscovery::Adapters::TalentlyftBoardSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 2, candidates.size
    assert_equal [ entries[0][0], entries[1][0] ], candidates.map { |candidate| candidate[:canonical_url] }
  end

  test "discovers additional boards from known hosted posting urls" do
    other_board = "https://other-company.talentlyft.com"
    url = "#{other_board}/jobs/senior-rails-engineer"
    source_scan = build_source_scan("board_urls" => [])
    Job.create!(
      title: "Senior Rails Engineer",
      company_name: "Other Company",
      canonical_url: url,
      source_url: url,
      apply_url: url,
      external_job_id: "senior-rails-engineer",
      fingerprint: "other-company::senior rails engineer::other-company.talentlyft.com::senior-rails-engineer",
      job_source: source_scan.job_source,
      lifecycle_state: :active
    )
    fetcher = FakeFetcher.new(
      "#{other_board}/sitemap.xml" => sitemap([ [ url, 1.day.ago.iso8601 ] ]),
      url => job_page(title: "Senior Rails Engineer", url:)
    )

    candidates = JobDiscovery::Adapters::TalentlyftBoardSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal [ url ], candidates.map { |candidate| candidate[:canonical_url] }
  end
end
