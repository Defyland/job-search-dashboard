require "test_helper"

class JobDiscovery::Adapters::HiringcafeJobsSitemapAdapterTest < ActiveSupport::TestCase
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

  INDEX_URL = "https://hiringcafe.com/job-posting-sitemap.xml".freeze
  CHUNK_URL = "https://hiringcafe.com/job-posting-sitemap/1/shard-0/chunk-2.xml".freeze
  OLD_CHUNK_URL = "https://hiringcafe.com/job-posting-sitemap/1/shard-0/chunk-1.xml".freeze

  def build_source_scan(settings = {})
    source = JobSource.create!(
      name: "HiringCafe Test",
      slug: "hiringcafe-test",
      host: "hiringcafe.com",
      base_url: "https://hiringcafe.com",
      source_kind: :aggregator,
      adapter_key: "hiringcafe_jobs_sitemap",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "max_chunks" => 1 }.merge(settings)
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
  end

  def sitemap_index
    <<~XML
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>#{OLD_CHUNK_URL}</loc></url>
        <url><loc>#{CHUNK_URL}</loc></url>
      </urlset>
    XML
  end

  def chunk(entries)
    rows = entries.map do |url, lastmod|
      "<url><loc>#{url}</loc><lastmod>#{lastmod}</lastmod></url>"
    end.join
    %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{rows}</urlset>)
  end

  def job_page(title:, company: "MKS2 Technologies", date_posted: 2.days.ago.iso8601, valid_through: 30.days.from_now.iso8601, location_type: "TELECOMMUTE")
    posting = {
      "@context" => "https://schema.org/",
      "@type" => "JobPosting",
      "title" => title,
      "description" => "<div><p>Build and maintain Ruby on Rails services and RESTful APIs.</p></div>",
      "identifier" => { "@type" => "PropertyValue", "name" => company, "value" => "nl3h0wecf6tgwpem" },
      "datePosted" => date_posted,
      "employmentType" => [ "FULL_TIME" ],
      "hiringOrganization" => { "@type" => "Organization", "name" => company },
      "jobLocationType" => location_type,
      "validThrough" => valid_through,
      "jobLocation" => { "@type" => "Place", "address" => { "@type" => "PostalAddress", "addressCountry" => "US" } }
    }
    %(<html><head><script type="application/ld+json">#{posting.to_json}</script></head><body></body></html>)
  end

  test "discovers jobs through the newest sitemap chunk and extracts the JobPosting block" do
    job_url = "https://hiringcafe.com/job/senior-ruby-engineer-mks2-technologies-united-states-abc123"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      INDEX_URL => sitemap_index,
      CHUNK_URL => chunk([ [ job_url, 1.day.ago.to_date.to_s ] ]),
      job_url => job_page(title: "Senior Ruby Engineer")
    )

    candidates = JobDiscovery::Adapters::HiringcafeJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    candidate = candidates.first
    assert_equal "Senior Ruby Engineer", candidate[:title]
    assert_equal "MKS2 Technologies", candidate[:company_name]
    assert_equal job_url, candidate[:canonical_url]
    assert_equal "Remote", candidate[:remote_text]
    assert_equal "nl3h0wecf6tgwpem", candidate[:external_job_id]
    assert_includes candidate[:description], "Ruby on Rails services"
    # The oldest chunk is not requested when max_chunks is 1.
    assert_not_includes fetcher.requests.map(&:first), OLD_CHUNK_URL
  end

  test "pins every request to the hiringcafe host" do
    job_url = "https://hiringcafe.com/job/senior-rails-engineer-acme-remote-abc123"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      INDEX_URL => sitemap_index,
      CHUNK_URL => chunk([ [ job_url, 1.day.ago.to_date.to_s ] ]),
      job_url => job_page(title: "Senior Rails Engineer")
    )

    JobDiscovery::Adapters::HiringcafeJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert fetcher.requests.all? { |_url, allowed_hosts| allowed_hosts == [ "hiringcafe.com" ] }
  end

  test "skips sitemap rows outside the window or outside the profile without fetching them" do
    fresh = "https://hiringcafe.com/job/senior-ruby-engineer-acme-remote-fresh1"
    stale = "https://hiringcafe.com/job/senior-ruby-engineer-acme-remote-stale1"
    unrelated = "https://hiringcafe.com/job/dental-assistant-acme-ohio-other1"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      INDEX_URL => sitemap_index,
      CHUNK_URL => chunk([
        [ fresh, 1.day.ago.to_date.to_s ],
        [ stale, 90.days.ago.to_date.to_s ],
        [ unrelated, 1.day.ago.to_date.to_s ]
      ]),
      fresh => job_page(title: "Senior Ruby Engineer")
    )

    candidates = JobDiscovery::Adapters::HiringcafeJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal [ fresh ], candidates.map { |candidate| candidate[:canonical_url] }
    fetched = fetcher.requests.map(&:first)
    assert_not_includes fetched, stale
    assert_not_includes fetched, unrelated
  end

  test "drops postings whose validThrough has already passed" do
    job_url = "https://hiringcafe.com/job/senior-ruby-engineer-acme-remote-expired"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      INDEX_URL => sitemap_index,
      CHUNK_URL => chunk([ [ job_url, 1.day.ago.to_date.to_s ] ]),
      job_url => job_page(title: "Senior Ruby Engineer", valid_through: 2.days.ago.iso8601)
    )

    candidates = JobDiscovery::Adapters::HiringcafeJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_empty candidates
  end

  test "ignores sitemap entries outside the allowed /job/ path" do
    disallowed = "https://hiringcafe.com/viewjob/senior-ruby-engineer-acme-remote-abc123"
    external = "https://example.com/job/senior-ruby-engineer-acme-remote-abc123"
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      INDEX_URL => sitemap_index,
      CHUNK_URL => chunk([ [ disallowed, 1.day.ago.to_date.to_s ], [ external, 1.day.ago.to_date.to_s ] ])
    )

    candidates = JobDiscovery::Adapters::HiringcafeJobsSitemapAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_empty candidates
    assert_equal 0, source_scan.reload.metadata["sitemap_urls_seen"]
  end
end
