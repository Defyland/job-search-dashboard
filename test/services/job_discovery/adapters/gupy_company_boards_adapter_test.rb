require "test_helper"

class JobDiscovery::Adapters::GupyCompanyBoardsAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5)
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
    detail_html = <<~HTML
      <html><body>
        <script type="application/ld+json">
          {"@context":"http://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Ruby on Rails Sênior","datePosted":"2026-06-04","description":"Vaga remota em Ruby on Rails","hiringOrganization":{"name":"Clicksign"}}
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
      reason: "seed",
      score: 90,
      match_strength: :strong,
      seniority: "senior",
      remote_text: "Remoto",
      location_text: "Brasil",
      stack_tags: [ "ruby" ]
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    board_html = <<~HTML
      <html><head><title>Clicksign</title></head><body>
        <a href="/jobs/11234166?jobBoardSource=gupy_public_page">Desenvolvedor(a) Ruby on Rails Sênior Trabalho Remoto Efetivo</a>
      </body></html>
    HTML
    detail_html = <<~HTML
      <html><body>
        <script type="application/ld+json">
          {"@context":"http://schema.org","@type":"JobPosting","title":"Desenvolvedor(a) Ruby on Rails Sênior","datePosted":"2026-06-04","description":"Vaga remota em Ruby on Rails","hiringOrganization":{"name":"Clicksign"}}
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
end
