require "test_helper"

class JobDiscovery::Adapters::CoodeshJobsSitemapAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "scans the public jobs sitemap and extracts strong matches from job detail pages" do
    source = JobSource.create!(
      name: "Coodesh Test",
      slug: "coodesh-test",
      host: "coodesh.com",
      base_url: "https://coodesh.com",
      source_kind: :platform,
      adapter_key: "coodesh_jobs_sitemap",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {}
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    sitemap_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset>
        <url>
          <loc>https://coodesh.com/jobs/senior-ruby-on-rails-engineer-123456</loc>
        </url>
        <url>
          <loc>https://coodesh.com/jobs/frontend-react-pleno-654321</loc>
        </url>
      </urlset>
    XML
    strong_job_html = <<~HTML
      <html>
        <body>
          <script>
            self.__next_f.push([1,"20:[{\\"job\\":{\\"title\\":\\"Senior Ruby on Rails Engineer\\",\\"company\\":{\\"company_name\\":\\"ExampleCo\\",\\"address\\":{\\"city\\":\\"Sao Paulo\\",\\"province\\":\\"SP\\",\\"country\\":\\"Brasil\\",\\"full_location\\":\\"Sao Paulo, SP, Brasil\\"}},\\"description\\":\\"<p>Ruby on Rails para produto core</p>\\",\\"requirements\\":[\\"Ruby on Rails\\",\\"APIs\\"],\\"differentials\\":[\\"React\\"],\\"benefits\\":[\\"Plano de saude\\"],\\"skills\\":[{\\"name\\":\\"Ruby\\"},{\\"name\\":\\"Ruby on Rails\\"},{\\"name\\":\\"React\\"}],\\"application_type\\":\\"platform\\",\\"external_url\\":\\"\\",\\"type_formatted\\":\\"CLT\\",\\"level_formatted\\":\\"Senior\\",\\"home_office_formatted\\":\\"Remota\\",\\"status_formatted\\":\\"Em progresso\\",\\"salary_range_formatted\\":\\"Negociavel\\",\\"publish_date\\":\\"#{3.days.ago.iso8601}\\",\\"created\\":\\"#{4.days.ago.iso8601}\\",\\"slug\\":\\"senior-ruby-on-rails-engineer-123456\\",\\"_id\\":\\"coodesh-strong-1\\"},\\"similarJobs\\":{\\"docs\\":[]}}]"])
          </script>
        </body>
      </html>
    HTML
    rejected_job_html = <<~HTML
      <html>
        <body>
          <script>
            self.__next_f.push([1,"20:[{\\"job\\":{\\"title\\":\\"Frontend React Pleno\\",\\"company\\":{\\"company_name\\":\\"OtherCo\\",\\"address\\":{\\"city\\":\\"Remote\\",\\"country\\":\\"Brasil\\"}},\\"description\\":\\"React\\",\\"skills\\":[{\\"name\\":\\"React\\"}],\\"publish_date\\":\\"#{2.days.ago.iso8601}\\",\\"created\\":\\"#{2.days.ago.iso8601}\\",\\"slug\\":\\"frontend-react-pleno-654321\\",\\"_id\\":\\"coodesh-reject-1\\",\\"home_office_formatted\\":\\"Remota\\",\\"status_formatted\\":\\"Em progresso\\"},\\"similarJobs\\":{\\"docs\\":[]}}]"])
          </script>
        </body>
      </html>
    HTML

    adapter = JobDiscovery::Adapters::CoodeshJobsSitemapAdapter.new(
      fetcher: FakeFetcher.new(
        "https://coodesh.com/sitemaps/jobs.xml" => sitemap_xml,
        "https://coodesh.com/jobs/senior-ruby-on-rails-engineer-123456" => strong_job_html,
        "https://coodesh.com/jobs/frontend-react-pleno-654321" => rejected_job_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "ExampleCo", candidates.first[:company_name]
    assert_equal "coodesh-strong-1", candidates.first[:external_job_id]
    assert_equal "https://coodesh.com/jobs/senior-ruby-on-rails-engineer-123456", candidates.first[:apply_url]
    assert_equal [ "ruby", "ruby on rails" ], candidates.first[:stack_tags].sort
  end

  test "discovers known coodesh urls even when they are not present in the sitemap" do
    source = JobSource.create!(
      name: "Coodesh Discovery",
      slug: "coodesh-discovery",
      host: "coodesh.com",
      base_url: "https://coodesh.com",
      source_kind: :platform,
      adapter_key: "coodesh_jobs_sitemap",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {}
    )
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Seed Coodesh Job",
      company_name: "SeedCo",
      apply_url: "https://coodesh.com/jobs/senior-react-native-engineer-777",
      canonical_url: "https://coodesh.com/jobs/senior-react-native-engineer-777",
      source_url: "https://coodesh.com/jobs/senior-react-native-engineer-777",
      fingerprint: "seed::coodesh::777",
      remote_text: "Remoto",
      location_text: "Brasil"
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    sitemap_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset></urlset>
    XML
    seeded_job_html = <<~HTML
      <html>
        <body>
          <script>
            self.__next_f.push([1,"20:[{\\"job\\":{\\"title\\":\\"Senior React Native Engineer\\",\\"company\\":{\\"company_name\\":\\"SeedCo\\",\\"address\\":{\\"country\\":\\"Brasil\\"}},\\"description\\":\\"React Native para produto mobile\\",\\"skills\\":[{\\"name\\":\\"React Native\\"}],\\"publish_date\\":\\"#{1.day.ago.iso8601}\\",\\"created\\":\\"#{2.days.ago.iso8601}\\",\\"slug\\":\\"senior-react-native-engineer-777\\",\\"_id\\":\\"coodesh-seed-777\\",\\"home_office_formatted\\":\\"Remota\\",\\"status_formatted\\":\\"Em progresso\\"},\\"similarJobs\\":{\\"docs\\":[]}}]"])
          </script>
        </body>
      </html>
    HTML

    adapter = JobDiscovery::Adapters::CoodeshJobsSitemapAdapter.new(
      fetcher: FakeFetcher.new(
        "https://coodesh.com/sitemaps/jobs.xml" => sitemap_xml,
        "https://coodesh.com/jobs/senior-react-native-engineer-777" => seeded_job_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "SeedCo", candidates.first[:company_name]
    assert_equal "https://coodesh.com/jobs/senior-react-native-engineer-777", candidates.first[:canonical_url]
  end
end
