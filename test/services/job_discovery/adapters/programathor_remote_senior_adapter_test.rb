require "test_helper"

class JobDiscovery::Adapters::ProgramathorRemoteSeniorAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5)
      @responses.fetch(url)
    end
  end

  test "scans the filtered programathor pages" do
    source = JobSource.create!(
      name: "ProgramaThor Test",
      slug: "programathor-test",
      host: "programathor.com.br",
      base_url: "https://programathor.com.br",
      source_kind: :platform,
      adapter_key: "programathor_remote_senior",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "max_pages" => 1 }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    listing_html = <<~HTML
      <html><body>
        <a href="/jobs/33485-desenvolvedor-a-react-senior-temporario">Desenvolvedor(a) React Sênior Temporário WeFit Remoto</a>
      </body></html>
    HTML
    detail_html = <<~HTML
      <html><head><title>Desenvolvedor(a) React Sênior Temporário - WeFit</title></head><body>
        Empresa WeFit Remoto React TypeScript Senior
      </body></html>
    HTML

    adapter = JobDiscovery::Adapters::ProgramathorRemoteSeniorAdapter.new(
      fetcher: FakeFetcher.new(
        "https://programathor.com.br/jobs-city/remoto?expertise=S%C3%AAnior" => listing_html,
        "https://programathor.com.br/jobs/33485-desenvolvedor-a-react-senior-temporario" => detail_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "https://programathor.com.br/jobs/33485-desenvolvedor-a-react-senior-temporario", candidates.first[:apply_url]
  end
end
