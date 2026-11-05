require "test_helper"

class JobDiscovery::Adapters::GupyCompanyBoardsAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :requested_urls

    def initialize(responses)
      @responses = responses
      @requested_urls = []
    end

    def call(url, limit: 5)
      @requested_urls << url
      @responses.fetch(url, "<html><body></body></html>")
    end
  end

  test "scans known gupy boards and extracts strong matches" do
    source = JobSource.create!(
      name: "Gupy Test",
      slug: "gupy-test",
      host: "gupy.io",
      base_url: "https://gupy.io",
      source_kind: :ats,
      adapter_key: "gupy_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "board_urls" => [ "https://clicksign.gupy.io/" ] }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    board_html = <<~HTML
      <html><head><title>Clicksign</title></head><body>
        <a href="/jobs/11234166?jobBoardSource=gupy_public_page">Desenvolvedor(a) Ruby on Rails Sênior Trabalho Remoto Efetivo</a>
      </body></html>
    HTML
    recent_date = 2.days.ago.to_date.iso8601
    detail_html = <<~HTML
      <html><body>
        <script type="application/ld+json">
          {"@context":"http://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Ruby on Rails Sênior","datePosted":"#{recent_date}","description":"Vaga remota em Ruby on Rails","hiringOrganization":{"name":"Clicksign"}}
        </script>
        <a href="/candidates/jobs/11234166/apply?jobBoardSource=gupy_public_page">Candidatar-se</a>
      </body></html>
    HTML

    adapter = JobDiscovery::Adapters::GupyCompanyBoardsAdapter.new(
      fetcher: FakeFetcher.new(
        "https://clicksign.gupy.io/" => board_html,
        "https://clicksign.gupy.io/jobs/11234166?jobBoardSource=gupy_public_page" => detail_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "https://clicksign.gupy.io/candidates/jobs/11234166/apply?jobBoardSource=gupy_public_page", candidates.first[:apply_url]
    assert_equal "Clicksign", candidates.first[:company_name]
  end

  test "discovers gupy boards from persisted jobs outside the gupy source bucket" do
    source = JobSource.create!(
      name: "Gupy Test",
      slug: "gupy-test-discovery",
      host: "gupy.io",
      base_url: "https://gupy.io",
      source_kind: :ats,
      adapter_key: "gupy_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {}
    )
    remoter_source = JobSource.create!(
      name: "Remotar",
      slug: "remotar-discovery",
      host: "remotar.com.br",
      base_url: "https://remotar.com.br",
      source_kind: :platform,
      adapter_key: "manual_only"
    )
    Job.create!(
      job_source: remoter_source,
      title: "Seed Gupy Job",
      company_name: "Clicksign",
      apply_url: "https://clicksign.gupy.io/jobs/11234166",
      canonical_url: "https://clicksign.gupy.io/jobs/11234166",
      source_url: "https://clicksign.gupy.io/jobs/11234166",
      fingerprint: "seed::clicksign::11234166",
      remote_text: "Remoto",
      location_text: "Brasil"
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    board_html = <<~HTML
      <html><head><title>Clicksign</title></head><body>
        <a href="/jobs/11234166?jobBoardSource=gupy_public_page">Desenvolvedor(a) Ruby on Rails Sênior Trabalho Remoto Efetivo</a>
      </body></html>
    HTML
    recent_date = 2.days.ago.to_date.iso8601
    detail_html = <<~HTML
      <html><body>
        <script type="application/ld+json">
          {"@context":"http://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Ruby on Rails Sênior","datePosted":"#{recent_date}","description":"Vaga remota em Ruby on Rails","hiringOrganization":{"name":"Clicksign"}}
        </script>
        <a href="/candidates/jobs/11234166/apply?jobBoardSource=gupy_public_page">Candidatar-se</a>
      </body></html>
    HTML

    adapter = JobDiscovery::Adapters::GupyCompanyBoardsAdapter.new(
      fetcher: FakeFetcher.new(
        "https://clicksign.gupy.io/" => board_html,
        "https://clicksign.gupy.io/jobs/11234166?jobBoardSource=gupy_public_page" => detail_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "https://clicksign.gupy.io/candidates/jobs/11234166/apply?jobBoardSource=gupy_public_page", candidates.first[:apply_url]
  end

  test "caps dynamically discovered boards at 25 and always keeps the configured ones" do
    source = JobSource.create!(
      name: "Gupy Test",
      slug: "gupy-test-board-cap",
      host: "gupy.io",
      base_url: "https://gupy.io",
      source_kind: :ats,
      adapter_key: "gupy_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "board_urls" => [ "https://clicksign.gupy.io/" ] }
    )
    remoter_source = JobSource.create!(
      name: "Remotar",
      slug: "remotar-board-cap",
      host: "remotar.com.br",
      base_url: "https://remotar.com.br",
      source_kind: :platform,
      adapter_key: "manual_only"
    )
    30.times do |index|
      host = format("board%02d.gupy.io", index)
      Job.create!(
        job_source: remoter_source,
        title: "Seed Gupy Job #{index}",
        company_name: "Board #{index}",
        apply_url: "https://#{host}/jobs/#{index + 1}",
        canonical_url: "https://#{host}/jobs/#{index + 1}",
        source_url: "https://#{host}/jobs/#{index + 1}",
        fingerprint: "seed::board#{index}::#{index + 1}",
        remote_text: "Remoto",
        location_text: "Brasil"
      )
    end

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    fetcher = FakeFetcher.new({})

    JobDiscovery::Adapters::GupyCompanyBoardsAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    board_urls = fetcher.requested_urls.select { |url| url.end_with?("/") && url.include?(".gupy.io") }
    assert_equal 26, board_urls.size
    assert_includes board_urls, "https://clicksign.gupy.io/"
  end

  test "keeps the query string out of the canonical url of a board listing" do
    source = create_source(settings: { "board_urls" => [ "https://clicksign.gupy.io/" ] })
    fetcher = FakeFetcher.new(
      "https://clicksign.gupy.io/" => board_html_with_listing,
      "https://clicksign.gupy.io/jobs/11234166?jobBoardSource=gupy_public_page" => detail_html
    )

    candidate = JobDiscovery::Adapters::GupyCompanyBoardsAdapter.new(fetcher:).scan(source_scan: create_source_scan(source), window_days: 20).first

    assert_equal "https://clicksign.gupy.io/jobs/11234166", candidate[:canonical_url]
    assert_equal "https://clicksign.gupy.io/jobs/11234166", candidate[:source_url]
    assert_includes fetcher.requested_urls, "https://clicksign.gupy.io/jobs/11234166?jobBoardSource=gupy_public_page", "the listing is still opened as the board links it"
  end

  test "counts distinct hosts toward the cap and never spends a slot on a configured board" do
    remove_fixture_gupy_jobs
    # The configured board sorts first, inside the window that discovery would otherwise fill.
    source = create_source(settings: { "board_urls" => [ "https://board00.gupy.io/" ] })
    30.times do |index|
      host = format("board%02d.gupy.io", index)
      seed_gupy_job(host:, id: 1)
      seed_gupy_job(host:, id: 2)
    end
    fetcher = FakeFetcher.new({})

    scan_boards(source, fetcher)

    discovered = board_requests(fetcher) - [ "https://board00.gupy.io/" ]
    assert_equal 25, discovered.uniq.size, "25 distinct discovered hosts, not 25 urls that repeat hosts"
    assert_equal 1, board_requests(fetcher).count("https://board00.gupy.io/"), "the configured board is scanned once"
  end

  test "rotates the discovered boards from one scan to the next, so every board is reached over the scans" do
    remove_fixture_gupy_jobs
    source = create_source
    30.times { |index| seed_gupy_job(host: format("board%02d.gupy.io", index), id: 1) }
    first_fetcher = FakeFetcher.new({})
    second_fetcher = FakeFetcher.new({})

    scan_boards(source, first_fetcher)
    scan_boards(source, second_fetcher)

    first_boards = board_requests(first_fetcher)
    second_boards = board_requests(second_fetcher)
    assert_equal 25, first_boards.size
    assert_equal 25, second_boards.size
    assert_not_equal first_boards.sort, second_boards.sort, "the second scan must not repeat the first one"
    assert_includes second_boards, "https://board29.gupy.io/", "boards past the first 25 get their turn"
    assert_equal 30, (first_boards | second_boards).size
  end

  test "never treats the gupy portal host as a company board" do
    remove_fixture_gupy_jobs
    source = create_source
    seed_gupy_job(host: "portal.gupy.io", id: 1)
    fetcher = FakeFetcher.new({})

    scan_boards(source, fetcher)

    assert_not_includes board_requests(fetcher), "https://portal.gupy.io/"
  end

  test "a board listing and the same portal listing link to one job when their canonical urls match" do
    # The fixture profiles are active too; deactivating them keeps the scan to the stack under test.
    SearchProfile.update_all(active: false)
    users(:one).search_profiles.create!(name: "Ruby na board e no portal", target_stacks: [ "ruby on rails" ])
    board_source = create_source(settings: { "board_urls" => [ "https://clicksign.gupy.io/" ] })
    portal_source = JobSource.create!(
      name: "Gupy Portal Cross Source",
      slug: "gupy-portal-cross-source",
      host: "portal.gupy.io",
      base_url: "https://portal.gupy.io",
      source_kind: :ats,
      adapter_key: "gupy_portal_search",
      supports_backfill: true,
      scan_window_days: 20
    )
    fetcher = RoutedFetcher.new(
      html: {
        "https://clicksign.gupy.io/" => board_html_with_listing,
        "https://clicksign.gupy.io/jobs/11234166?jobBoardSource=gupy_public_page" => detail_html(company: "Clicksign Tecnologia S.A.")
      }
    )

    result = JobDiscovery::Orchestrator.new(
      window_days: 20,
      source_scope: JobSource.where(id: [ board_source.id, portal_source.id ]),
      registry: RoutingRegistry.new(fetcher)
    ).call

    job = Job.find_by!(canonical_url: "https://clicksign.gupy.io/jobs/11234166")
    discovered = result.search_run.discovered_jobs.where(external_job_id: "11234166").to_a
    assert_equal 2, discovered.size, "both sources must have found the listing"
    assert_equal [ job.id, job.id ], discovered.map(&:job_id)
    assert_equal 1, Job.where(canonical_url: "https://clicksign.gupy.io/jobs/11234166").count
    assert_equal [ job.canonical_url ], discovered.map(&:canonical_url).uniq, "the board row must store the same canonical url as the job"
  end

  private
    class RoutedFetcher
      attr_reader :requested_urls

      def initialize(html:)
        @html = html
        @requested_urls = []
      end

      def call(url, limit: 5)
        @requested_urls << url
        return portal_search_body if url.start_with?("https://portal.gupy.io/api/job-search/jobs")

        @html.fetch(url, "<html><body></body></html>")
      end

      private
        def portal_search_body
          {
            "data" => [
              {
                "id" => 11_234_166,
                "name" => "Desenvolvedor(a) Ruby on Rails Sênior",
                "description" => "Vaga remota em Ruby on Rails",
                "careerPageName" => "VENHA SER",
                "publishedDate" => 2.days.ago.iso8601,
                "workplaceType" => "remote",
                "jobUrl" => "https://clicksign.gupy.io/job/opaque-token?jobBoardSource=gupy_portal"
              }
            ],
            "pagination" => { "total" => 1, "limit" => 100, "offset" => 0 }
          }.to_json
        end
    end

    # The portal payload and the board page both point at the same listing, under different company names.
    class RoutingRegistry
      def initialize(fetcher)
        @fetcher = fetcher
      end

      def supports?(_adapter_key)
        true
      end

      def fetch(adapter_key)
        fetcher = @fetcher
        Class.new(JobDiscovery::Registry.new.fetch(adapter_key)) do
          define_method(:initialize) { |policy: nil| super(fetcher:, policy:) }
        end
      end
    end

    def create_source(settings: {}, slug: "gupy-test-#{SecureRandom.hex(4)}")
      JobSource.create!(
        name: "Gupy Test",
        slug:,
        host: "gupy.io",
        base_url: "https://gupy.io",
        source_kind: :ats,
        adapter_key: "gupy_company_boards",
        supports_backfill: true,
        scan_window_days: 20,
        settings:
      )
    end

    def create_source_scan(source)
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end

    def scan_boards(source, fetcher)
      JobDiscovery::Adapters::GupyCompanyBoardsAdapter.new(fetcher:).scan(source_scan: create_source_scan(source), window_days: 20)
    end

    def board_requests(fetcher)
      fetcher.requested_urls.select { |url| url.end_with?("/") && url.include?(".gupy.io") }
    end

    # Fixture listings on gupy hosts would add discovered boards to the counts these tests assert.
    # Discovery only reads active jobs, so they are expired instead of deleted, since other fixtures reference them.
    def remove_fixture_gupy_jobs
      Job.where("canonical_url LIKE ?", "%gupy.io%").update_all(lifecycle_state: Job.lifecycle_states[:expired])
    end

    def seed_gupy_job(host:, id:)
      url = "https://#{host}/jobs/#{id}"
      Job.create!(
        job_source: remoter_source,
        title: "Seed Gupy Job #{host} #{id}",
        company_name: host,
        apply_url: url,
        canonical_url: url,
        source_url: url,
        fingerprint: "seed::#{host}::#{id}",
        remote_text: "Remoto",
        location_text: "Brasil"
      )
    end

    def remoter_source
      @remoter_source ||= JobSource.create!(
        name: "Remotar",
        slug: "remotar-#{SecureRandom.hex(3)}",
        host: "remotar.com.br",
        base_url: "https://remotar.com.br",
        source_kind: :platform,
        adapter_key: "manual_only"
      )
    end

    def board_html_with_listing
      <<~HTML
        <html><head><title>Clicksign</title></head><body>
          <a href="/jobs/11234166?jobBoardSource=gupy_public_page">Desenvolvedor(a) Ruby on Rails Sênior Trabalho Remoto Efetivo</a>
        </body></html>
      HTML
    end

    def detail_html(company: "Clicksign")
      <<~HTML
        <html><body>
          <script type="application/ld+json">
            {"@context":"http://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Ruby on Rails Sênior","datePosted":"#{2.days.ago.to_date.iso8601}","description":"Vaga remota em Ruby on Rails","hiringOrganization":{"name":"#{company}"}}
          </script>
          <a href="/candidates/jobs/11234166/apply?jobBoardSource=gupy_public_page">Candidatar-se</a>
        </body></html>
      HTML
    end
end
