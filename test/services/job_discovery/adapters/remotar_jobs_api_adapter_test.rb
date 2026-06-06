require "test_helper"

class JobDiscovery::Adapters::RemotarJobsApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5)
      @responses.fetch(url)
    end
  end

  test "scans remotar api pages and extracts external application links" do
    source = JobSource.create!(
      name: "Remotar Test",
      slug: "remotar-test",
      host: "remotar.com.br",
      base_url: "https://remotar.com.br",
      source_kind: :platform,
      adapter_key: "remotar_jobs_api",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "max_pages" => 1 }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    response_body = {
      meta: { current_page: 1, last_page: 1 },
      data: [
        {
          "id" => 139443,
          "title" => "Senior Ruby on Rails Engineer",
          "subtitle" => "Liderança técnica em Ruby on Rails",
          "description" => "<p>Vaga 100% remota</p>",
          "active" => true,
          "type" => "remote",
          "updatedAt" => "2026-06-05T20:09:32.116-03:00",
          "createdAt" => "2026-06-05T20:09:30.030-03:00",
          "externalLink" => "https://lwsa.inhire.app/vagas/f44362ce-96f5-4952-ae0b-28ae3c35596d/vindi-or-coordenador-de-sistemas-ruby-or-remoto",
          "integrationSource" => "inhire",
          "country" => "Brazil",
          "company" => { "name" => "LWSA", "link" => "https://lwsa.tech/" },
          "jobRequirements" => [ { "description" => "Domínio em Ruby, Rails e APIs." } ]
        },
        {
          "id" => 139500,
          "title" => "Designer Pleno",
          "description" => "<p>Remoto</p>",
          "active" => true,
          "type" => "remote",
          "updatedAt" => "2026-06-05T20:09:32.116-03:00",
          "createdAt" => "2026-06-05T20:09:30.030-03:00",
          "externalLink" => "https://example.com/jobs/designer",
          "integrationSource" => "manual",
          "company" => { "name" => "Example" }
        }
      ]
    }.to_json

    adapter = JobDiscovery::Adapters::RemotarJobsApiAdapter.new(
      fetcher: FakeFetcher.new("https://api.remotar.com.br/jobs?active=true&page=1" => response_body)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "LWSA", candidates.first[:company_name]
    assert_equal "https://lwsa.inhire.app/vagas/f44362ce-96f5-4952-ae0b-28ae3c35596d/vindi-or-coordenador-de-sistemas-ruby-or-remoto", candidates.first[:apply_url]
  end
end
