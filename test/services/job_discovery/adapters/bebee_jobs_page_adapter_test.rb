require "test_helper"

class JobDiscovery::Adapters::BebeeJobsPageAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(response)
      @response = response
    end

    def call(url, limit: 5)
      @response
    end
  end

  test "extracts jobs from the embedded Next.js payload and applies the profile policy" do
    source = job_sources(:workable)
    source.update!(
      adapter_key: "bebee_jobs_page",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "search_queries" => [ "ruby" ], "remote_filter" => "full_remote" }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    payload_hash = {
      "query" => "ruby",
      "country" => "br",
      "jobs" => [
        {
          "id" => "ss-br-1abc",
          "title" => "Engenheiro de Software Ruby on Rails Sênior",
          "publisher_name" => "Lyncas",
          "description" => "Vaga remota para Ruby on Rails.",
          "started_date" => 2.days.ago.change(usec: 0).iso8601,
          "url" => "https://lyncas.inhire.app/vagas/c1c0009e-a380-44dc-a322-575fd3ee9543/-",
          "remote_policy" => "full_remote",
          "location_name" => "BR",
          "contract_type" => "full_time",
          "primary_keywords" => %w[ruby rails]
        },
        {
          "id" => "ss-br-2def",
          "title" => "Product Designer",
          "publisher_name" => "Studio",
          "description" => "Design de produto.",
          "started_date" => 1.day.ago.change(usec: 0).iso8601,
          "url" => "https://example.com/product-designer",
          "remote_policy" => "hybrid",
          "location_name" => "SP"
        }
      ]
    }
    escaped_payload = JSON.generate(JSON.generate(payload_hash))[1..-2]
    html = "self.__next_f.push([1,\"#{escaped_payload}\"]);"

    adapter = JobDiscovery::Adapters::BebeeJobsPageAdapter.new(
      fetcher: FakeFetcher.new(html)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Lyncas", candidates.first[:company_name]
    assert_equal "ss-br-1abc", candidates.first[:external_job_id]
    assert_equal "https://lyncas.inhire.app/vagas/c1c0009e-a380-44dc-a322-575fd3ee9543/-", candidates.first[:apply_url]
    assert_equal "100% Remoto", candidates.first[:remote_text]
  end

  test "returns an empty array when the page has no embedded jobs payload" do
    source = job_sources(:workable)
    source.update!(
      adapter_key: "bebee_jobs_page",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "search_queries" => [ "ruby" ] }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    adapter = JobDiscovery::Adapters::BebeeJobsPageAdapter.new(
      fetcher: FakeFetcher.new("<html><body>no data</body></html>")
    )

    assert_empty adapter.scan(source_scan:, window_days: 20)
  end
end
