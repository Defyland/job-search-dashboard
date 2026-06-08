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

    detail_html = <<~HTML
      <html>
        <head>
          <link rel="canonical" href="https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior" />
          <script type="application/ld+json">
            {"@context":"https://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Front-end React/Next.js Sênior","datePosted":"27/05/2026 14:34:36","description":"React e Next.js remoto","hiringOrganization":{"name":"Maxxi"}}
          </script>
        </head>
        <body>
          <a href="https://talent.recrutei.com.br/maxxi/145107/signup?utm_medium=btn-details-page">Candidatar-se agora</a>
          <script id="__NEXT_DATA__" type="application/json">
            {"props":{"pageProps":{"retorno":{"company":{"company":{"name":"Maxxi","label":"maxxi"}},"vacancy":{"id":145107,"title":"Desenvolvedor(a) Front-end React/Next.js Sênior","description":"<p>React e Typescript remoto</p>","published_at":"27/05/2026 14:34:36","created_at":"2026-05-27T17:34:36.000000Z","public_link":"https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior","country":"Brasil","remote":1,"location":"Remoto","expired":false,"regime":{"description":"CLT ou PJ"}}}}}}
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
            {"@context":"https://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Front-end React/Next.js Sênior","datePosted":"27/05/2026 14:34:36","description":"React e Next.js remoto","hiringOrganization":{"name":"Maxxi"}}
          </script>
        </head>
        <body>
          <a href="https://talent.recrutei.com.br/maxxi/145107/signup">Candidatar-se agora</a>
          <script id="__NEXT_DATA__" type="application/json">
            {"props":{"pageProps":{"retorno":{"company":{"company":{"name":"Maxxi","label":"maxxi"}},"vacancy":{"id":145107,"title":"Desenvolvedor(a) Front-end React/Next.js Sênior","description":"<p>React e Typescript remoto</p>","published_at":"27/05/2026 14:34:36","created_at":"2026-05-27T17:34:36.000000Z","public_link":"https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior","country":"Brasil","remote":1,"location":"Remoto","expired":false}}}}}
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
