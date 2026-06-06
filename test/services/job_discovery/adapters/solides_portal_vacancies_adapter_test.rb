require "test_helper"

class JobDiscovery::Adapters::SolidesPortalVacanciesAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def call(url, limit: 5, headers: {})
      @calls << url
      @responses.fetch(url)
    end
  end

  test "scans solides search results and extracts strong remote senior matches" do
    source = build_source(settings: { "search_queries" => [ "react" ], "max_pages" => 1 })
    source_scan = build_source_scan(source:)

    detail_url = "https://vagas.solides.com.br/vaga/826827/desenvolvedor-react-node-senior"
    fetcher = FakeFetcher.new(
      "https://apigw.solides.com.br/jobs/v3/portal-vacancies-new/?title=react&page=1" => search_response([
        {
          "id" => 826827,
          "title" => "Desenvolvedor React/Node - Sênior",
          "companyName" => "SBM Technology",
          "description" => "<p>React remoto</p>",
          "redirectLink" => "https://sbmtechnology.solides.jobs/vacancies/826827?origem=portal",
          "jobType" => "remoto",
          "createdAt" => 3.days.ago.to_date.iso8601
        }
      ]),
      detail_url => detail_html(
        id: 826827,
        title: "Desenvolvedor React/Node - Sênior",
        company_name: "SBM Technology",
        description: "<p>React remoto Brasil</p>",
        redirect_link: "https://sbmtechnology.solides.jobs/vacancies/826827?origem=portal",
        created_at: 3.days.ago.to_date.iso8601,
        affirmative: []
      )
    )

    candidates = JobDiscovery::Adapters::SolidesPortalVacanciesAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "SBM Technology", candidates.first[:company_name]
    assert_equal "826827", candidates.first[:external_job_id]
    assert_equal "https://sbmtechnology.solides.jobs/vacancies/826827?origem=portal", candidates.first[:apply_url]
  end

  test "dedupes the same solides vacancy across multiple search queries" do
    source = build_source(settings: { "search_queries" => [ "react", "rails" ], "max_pages" => 1 })
    source_scan = build_source_scan(source:)

    detail_url = "https://vagas.solides.com.br/vaga/826827/desenvolvedor-react-node-senior"
    search_payload = search_response([
      {
        "id" => 826827,
        "title" => "Desenvolvedor React/Node - Sênior",
        "companyName" => "SBM Technology",
        "description" => "<p>React remoto</p>",
        "redirectLink" => "https://sbmtechnology.solides.jobs/vacancies/826827?origem=portal",
        "jobType" => "remoto",
        "createdAt" => 2.days.ago.to_date.iso8601
      }
    ])
    fetcher = FakeFetcher.new(
      "https://apigw.solides.com.br/jobs/v3/portal-vacancies-new/?title=react&page=1" => search_payload,
      "https://apigw.solides.com.br/jobs/v3/portal-vacancies-new/?title=rails&page=1" => search_payload,
      detail_url => detail_html(
        id: 826827,
        title: "Desenvolvedor React/Node - Sênior",
        company_name: "SBM Technology",
        description: "<p>React remoto Brasil</p>",
        redirect_link: "https://sbmtechnology.solides.jobs/vacancies/826827?origem=portal",
        created_at: 2.days.ago.to_date.iso8601,
        affirmative: []
      )
    )

    candidates = JobDiscovery::Adapters::SolidesPortalVacanciesAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal 1, fetcher.calls.count(detail_url)
  end

  test "rejects women-only affirmative solides jobs in the backend policy" do
    source = build_source(settings: { "search_queries" => [ "react" ], "max_pages" => 1 })
    source_scan = build_source_scan(source:)

    detail_url = "https://vagas.solides.com.br/vaga/999001/desenvolvedora-react-senior"
    fetcher = FakeFetcher.new(
      "https://apigw.solides.com.br/jobs/v3/portal-vacancies-new/?title=react&page=1" => search_response([
        {
          "id" => 999001,
          "title" => "Desenvolvedora React Sênior",
          "companyName" => "Example",
          "description" => "<p>Remoto Brasil</p>",
          "redirectLink" => "https://example.solides.jobs/vacancies/999001?origem=portal",
          "jobType" => "remoto",
          "createdAt" => 1.day.ago.to_date.iso8601
        }
      ]),
      detail_url => detail_html(
        id: 999001,
        title: "Desenvolvedora React Sênior",
        company_name: "Example",
        description: "<p>React remoto Brasil</p>",
        redirect_link: "https://example.solides.jobs/vacancies/999001?origem=portal",
        created_at: 1.day.ago.to_date.iso8601,
        affirmative: [ { "id" => 1, "name" => "Vaga afirmativa para Mulheres" } ]
      )
    )

    candidates = JobDiscovery::Adapters::SolidesPortalVacanciesAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "rejected", candidates.first[:classification]
    assert_equal "vaga afirmativa para mulheres", candidates.first[:exclusion_reason]
  end

  test "stops after the first stale solides page outside the requested window" do
    source = build_source(settings: { "search_queries" => [ "react" ], "max_pages" => 3 })
    source_scan = build_source_scan(source:)

    fetcher = FakeFetcher.new(
      "https://apigw.solides.com.br/jobs/v3/portal-vacancies-new/?title=react&page=1" => search_response([
        {
          "id" => 111001,
          "title" => "Desenvolvedor React Sênior",
          "companyName" => "Old Co",
          "description" => "<p>Remoto</p>",
          "redirectLink" => "https://oldco.solides.jobs/vacancies/111001?origem=portal",
          "jobType" => "remoto",
          "createdAt" => 45.days.ago.to_date.iso8601
        }
      ])
    )

    candidates = JobDiscovery::Adapters::SolidesPortalVacanciesAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_empty candidates
    assert_equal 1, source_scan.reload.pages_scanned
  end

  private
    def build_source(settings:)
      JobSource.create!(
        name: "Sólides Test",
        slug: "solides-test-#{SecureRandom.hex(4)}",
        host: "vagas.solides.com.br",
        base_url: "https://vagas.solides.com.br",
        source_kind: :ats,
        adapter_key: "solides_portal_vacancies",
        supports_backfill: true,
        scan_window_days: 20,
        settings:
      )
    end

    def build_source_scan(source:)
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end

    def search_response(jobs)
      {
        "success" => true,
        "data" => {
          "count" => jobs.size,
          "currentPage" => 1,
          "totalPages" => 1,
          "data" => jobs
        }
      }.to_json
    end

    def detail_html(id:, title:, company_name:, description:, redirect_link:, created_at:, affirmative:)
      <<~HTML
        <html>
          <head>
            <link rel="canonical" href="https://vagas.solides.com.br/vaga/#{id}/#{title.parameterize}" />
          </head>
          <body>
            <script id="__NEXT_DATA__" type="application/json">
              {"props":{"pageProps":{"vacancy":{"id":#{id},"title":"#{title}","companyName":"#{company_name}","description":"#{description}","redirectLink":"#{redirect_link}","createdAt":"#{created_at}","currentState":"em_andamento","paymentUpToDate":true,"companyActivated":true,"jobsActivated":true,"receivingResume":true,"jobType":"remoto","affirmative":#{affirmative.to_json},"city":{"name":"Sao Paulo"},"state":{"name":"SP"},"address":{"country":{"name":"Brasil"}}}}}}
            </script>
          </body>
        </html>
      HTML
    end
end
