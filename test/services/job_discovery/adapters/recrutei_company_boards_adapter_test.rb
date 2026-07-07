require "test_helper"

class JobDiscovery::Adapters::RecruteiCompanyBoardsAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "scans configured vacancy urls and extracts strong matches from detail pages" do
    source = JobSource.create!(
      name: "Recrutei Test",
      slug: "recrutei-test",
      host: "jobs.recrutei.com.br",
      base_url: "https://jobs.recrutei.com.br",
      source_kind: :ats,
      adapter_key: "recrutei_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        "vacancy_urls" => [
          "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior"
        ]
      }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    published_at = 2.days.ago.strftime("%d/%m/%Y %H:%M:%S")
    created_at = 2.days.ago.iso8601

    detail_html = <<~HTML
      <html>
        <head>
          <link rel="canonical" href="https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior" />
          <script type="application/ld+json">
            {"@context":"https://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Front-end React/Next.js Sênior","datePosted":"#{published_at}","description":"React e Next.js remoto","hiringOrganization":{"name":"Maxxi"}}
          </script>
        </head>
        <body>
          <a href="https://talent.recrutei.com.br/maxxi/145107/signup?utm_medium=btn-details-page">Candidatar-se agora</a>
          <script id="__NEXT_DATA__" type="application/json">
            {"props":{"pageProps":{"retorno":{"company":{"company":{"name":"Maxxi","label":"maxxi"}},"vacancy":{"id":145107,"title":"Desenvolvedor(a) Front-end React/Next.js Sênior","description":"<p>React e Typescript remoto</p>","published_at":"#{published_at}","created_at":"#{created_at}","public_link":"https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior","country":"Brasil","remote":1,"location":"Remoto","expired":false,"regime":{"description":"CLT ou PJ"}}}}}}
          </script>
        </body>
      </html>
    HTML

    adapter = JobDiscovery::Adapters::RecruteiCompanyBoardsAdapter.new(
      fetcher: FakeFetcher.new(
        "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior" => detail_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Maxxi", candidates.first[:company_name]
    assert_equal "145107", candidates.first[:external_job_id]
    assert_equal "https://talent.recrutei.com.br/maxxi/145107/signup?utm_medium=btn-details-page", candidates.first[:apply_url]
  end

  test "scans configured Thera frontend vacancy and accepts react context" do
    source = JobSource.create!(
      name: "Recrutei Thera",
      slug: "recrutei-thera",
      host: "jobs.recrutei.com.br",
      base_url: "https://jobs.recrutei.com.br",
      source_kind: :ats,
      adapter_key: "recrutei_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        "vacancy_urls" => [
          "https://jobs.recrutei.com.br/thera-consulting/vacancy/149473-desenvolvedora-frontend-senior"
        ]
      }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    published_at = 1.day.ago.strftime("%d/%m/%Y %H:%M:%S")
    created_at = 1.day.ago.iso8601

    detail_html = <<~HTML
      <html>
        <head>
          <link rel="canonical" href="https://jobs.recrutei.com.br/thera-consulting/vacancy/149473-desenvolvedora-frontend-senior" />
          <script type="application/ld+json">
            {"@context":"https://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Frontend Sênior","datePosted":"#{published_at}","description":"React e Next.js remoto","hiringOrganization":{"name":"THERA CONSULTING"}}
          </script>
        </head>
        <body>
          <a href="https://talent.recrutei.com.br/thera-consulting/149473/signup?utm_medium=btn-details-page">Candidatar-se agora</a>
          <script id="__NEXT_DATA__" type="application/json">
            {"props":{"pageProps":{"retorno":{"company":{"company":{"name":"THERA CONSULTING","label":"thera-consulting"}},"vacancy":{"id":149473,"title":"Desenvolvedor(a) Frontend Sênior","description":"<p>Boa experiência com arquitetura de aplicações React e componentização. React e Next.js. TypeScript.</p>","published_at":"#{published_at}","created_at":"#{created_at}","public_link":"https://jobs.recrutei.com.br/thera-consulting/vacancy/149473-desenvolvedora-frontend-senior","country":"Brasil","remote":1,"location":"Remoto","expired":false,"regime":{"description":"PJ"}}}}}}
          </script>
        </body>
      </html>
    HTML

    adapter = JobDiscovery::Adapters::RecruteiCompanyBoardsAdapter.new(
      fetcher: FakeFetcher.new(
        "https://jobs.recrutei.com.br/thera-consulting/vacancy/149473-desenvolvedora-frontend-senior" => detail_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "THERA CONSULTING", candidates.first[:company_name]
    assert_equal "149473", candidates.first[:external_job_id]
    assert_equal "https://talent.recrutei.com.br/thera-consulting/149473/signup?utm_medium=btn-details-page", candidates.first[:apply_url]
  end

  test "discovers company labels from persisted recrutei jobs and expands from the vacancies board" do
    source = JobSource.create!(
      name: "Recrutei Discovery",
      slug: "recrutei-discovery",
      host: "jobs.recrutei.com.br",
      base_url: "https://jobs.recrutei.com.br",
      source_kind: :ats,
      adapter_key: "recrutei_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {}
    )
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Seed Recrutei Job",
      company_name: "Maxxi",
      apply_url: "https://talent.recrutei.com.br/maxxi/145107/signup",
      canonical_url: "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior",
      source_url: "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior",
      fingerprint: "seed::recrutei::145107",
      remote_text: "Remoto",
      location_text: "Brasil"
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    published_at = 2.days.ago.strftime("%d/%m/%Y %H:%M:%S")
    created_at = 2.days.ago.iso8601

    board_html = <<~HTML
      <html><body>
        <a href="/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior">Detalhes</a>
      </body></html>
    HTML
    detail_html = <<~HTML
      <html>
        <head>
          <link rel="canonical" href="https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior" />
          <script type="application/ld+json">
            {"@context":"https://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Front-end React/Next.js Sênior","datePosted":"#{published_at}","description":"React e Next.js remoto","hiringOrganization":{"name":"Maxxi"}}
          </script>
        </head>
        <body>
          <a href="https://talent.recrutei.com.br/maxxi/145107/signup">Candidatar-se agora</a>
          <script id="__NEXT_DATA__" type="application/json">
            {"props":{"pageProps":{"retorno":{"company":{"company":{"name":"Maxxi","label":"maxxi"}},"vacancy":{"id":145107,"title":"Desenvolvedor(a) Front-end React/Next.js Sênior","description":"<p>React e Typescript remoto</p>","published_at":"#{published_at}","created_at":"#{created_at}","public_link":"https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior","country":"Brasil","remote":1,"location":"Remoto","expired":false}}}}}
          </script>
        </body>
      </html>
    HTML

    adapter = JobDiscovery::Adapters::RecruteiCompanyBoardsAdapter.new(
      fetcher: FakeFetcher.new(
        "https://jobs.recrutei.com.br/maxxi/vacancies" => board_html,
        "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior" => detail_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior", candidates.first[:canonical_url]
  end
end
