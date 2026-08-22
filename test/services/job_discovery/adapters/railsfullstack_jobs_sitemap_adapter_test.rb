require "test_helper"

class JobDiscovery::Adapters::RailsfullstackJobsSitemapAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "uses the SSR remote collection without fetching individual job pages" do
    collection_url = "https://www.railsfullstack.com/collections/remote-full-stack-rails-jobs"
    source_scan = build_source_scan(max_jobs: 40, collection_urls: [ collection_url ])
    jobs = [
      {
        "id" => 20_173,
        "title" => "Senior Full Stack Engineer (Ruby on Rails)",
        "company" => "Pixelmatters",
        "slug" => "senior-full-stack-engineer-ruby-on-rails-pixelmatters-portugal",
        "location" => "Portugal",
        "remote_type" => "remote",
        "posted_at" => 2.days.ago.iso8601,
        "last_seen_at" => 1.hour.ago.iso8601,
        "apply_url" => "https://pixelmatters.example/jobs/rails",
        "description" => "Build a remote Ruby on Rails and React product.",
        "tags" => [ "Ruby on Rails", "React" ],
        "salary_display" => "EUR 50K-70K",
        "hidden" => false
      },
      {
        "id" => 20_174,
        "title" => "Junior Ruby Developer",
        "company" => "Ignored",
        "slug" => "junior-ruby-developer-ignored",
        "posted_at" => 1.day.ago.iso8601,
        "hidden" => false
      }
    ]
    collection_html = <<~HTML
      <html><body><div id="app" data-page="#{ERB::Util.html_escape({ props: { jobs: } }.to_json)}"></div></body></html>
    HTML
    adapter = JobDiscovery::Adapters::RailsfullstackJobsSitemapAdapter.new(
      fetcher: FakeFetcher.new(collection_url => collection_html)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    candidate = candidates.first
    assert_equal "strong", candidate[:classification]
    assert_equal "Pixelmatters", candidate[:company_name]
    assert_equal "remote | Portugal", candidate[:remote_text]
    assert_equal "https://pixelmatters.example/jobs/rails", candidate[:apply_url]
    assert_equal "https://railsfullstack.com/jobs/senior-full-stack-engineer-ruby-on-rails-pixelmatters-portugal", candidate[:canonical_url]
    assert_equal 1, source_scan.reload.pages_scanned
  end

  test "scans the jobs sitemap and extracts recent remote JSON-LD postings" do
    source_scan = build_source_scan(max_jobs: 2)
    sitemap_url = "https://www.railsfullstack.com/sitemap.xml"
    jobs_sitemap_url = "https://www.railsfullstack.com/sitemaps/jobs/1.xml"
    active_url = "https://www.railsfullstack.com/jobs/senior-ruby-on-rails-engineer-acme"
    expired_url = "https://www.railsfullstack.com/jobs/senior-ruby-developer-oldco"
    ignored_url = "https://www.railsfullstack.com/jobs/senior-react-engineer-ignored"

    sitemap_index = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap><loc>https://www.railsfullstack.com/sitemaps/static.xml</loc></sitemap>
        <sitemap><loc>#{jobs_sitemap_url}</loc></sitemap>
      </sitemapindex>
    XML
    jobs_sitemap = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>#{active_url}</loc><lastmod>2026-08-18T12:00:00Z</lastmod></url>
        <url><loc>#{expired_url}</loc><lastmod>2026-08-18T11:00:00Z</lastmod></url>
        <url><loc>#{ignored_url}</loc><lastmod>2026-08-18T10:00:00Z</lastmod></url>
      </urlset>
    XML

    adapter = JobDiscovery::Adapters::RailsfullstackJobsSitemapAdapter.new(
      fetcher: FakeFetcher.new(
        sitemap_url => sitemap_index,
        jobs_sitemap_url => jobs_sitemap,
        active_url => job_html(
          title: "Senior Ruby on Rails Engineer",
          company_name: "Acme",
          identifier: "railsfullstack-acme-1",
          date_posted: "2026-08-17T12:00:00Z",
          valid_through: "2026-08-24T12:00:00Z",
          canonical_url: active_url,
          apply_url: "https://acme.example/apply/rails"
        ),
        expired_url => job_html(
          title: "Senior Ruby Developer",
          company_name: "OldCo",
          identifier: "railsfullstack-oldco-1",
          date_posted: "2026-08-16T12:00:00Z",
          valid_through: "2026-08-18T12:00:00Z",
          canonical_url: expired_url
        )
      )
    )

    travel_to Time.zone.parse("2026-08-19 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 2, candidates.size

      active = candidates.find { |candidate| candidate[:external_job_id] == "railsfullstack-acme-1" }
      assert_equal "strong", active[:classification]
      assert_equal "Acme", active[:company_name]
      assert_equal "Remote", active[:remote_text]
      assert_equal "Portugal", active[:location_text]
      assert_equal "https://acme.example/apply/rails", active[:apply_url]
      assert_equal active_url, active[:canonical_url]

      expired = candidates.find { |candidate| candidate[:external_job_id] == "railsfullstack-oldco-1" }
      assert_equal "expired", expired[:classification]
      assert_match(/validade/, expired[:reason])
      assert_equal 4, source_scan.reload.pages_scanned
    end
  end

  private
    def build_source_scan(max_jobs:, collection_urls: [])
      source = JobSource.create!(
        name: "RailsFullstack Test",
        slug: "railsfullstack-test",
        host: "railsfullstack.com",
        base_url: "https://www.railsfullstack.com",
        source_kind: :platform,
        adapter_key: "railsfullstack_jobs_sitemap",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          "collection_urls" => collection_urls,
          "sitemap_url" => "https://www.railsfullstack.com/sitemap.xml",
          "max_jobs" => max_jobs
        }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end

    def job_html(title:, company_name:, identifier:, date_posted:, valid_through:, canonical_url:, apply_url: nil)
      posting = {
        "@context" => "https://schema.org",
        "@type" => "JobPosting",
        "title" => title,
        "description" => "Remote Ruby on Rails role for a distributed team.",
        "datePosted" => date_posted,
        "validThrough" => valid_through,
        "identifier" => { "@type" => "PropertyValue", "value" => identifier },
        "hiringOrganization" => { "name" => company_name },
        "jobLocationType" => "TELECOMMUTE",
        "applicantLocationRequirements" => { "@type" => "Country", "name" => "Portugal" },
        "url" => canonical_url,
        "directApply" => true
      }
      apply_link = apply_url ? %(<a href="#{apply_url}">Apply now</a>) : ""

      <<~HTML
        <html>
          <head>
            <link rel="canonical" href="#{canonical_url}">
            <script type="application/ld+json">#{posting.to_json}</script>
          </head>
          <body>#{apply_link}</body>
        </html>
      HTML
    end
end
