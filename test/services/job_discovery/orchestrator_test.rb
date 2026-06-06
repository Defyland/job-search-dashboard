require "test_helper"

class JobDiscovery::OrchestratorTest < ActiveSupport::TestCase
  class FakeAdapter
    def scan(source_scan:, window_days:)
      [
        {
          classification: "strong",
          title: "Senior Ruby on Rails Engineer",
          company_name: "Clicksign",
          apply_url: "https://clicksign.gupy.io/candidates/jobs/11234166/apply",
          canonical_url: "https://clicksign.gupy.io/jobs/11234166",
          source_url: "https://clicksign.gupy.io/jobs/11234166",
          external_job_id: "11234166",
          fingerprint: "clicksign::senior ruby on rails engineer::clicksign.gupy.io::11234166",
          remote_text: "Remoto Brasil",
          location_text: "Brasil",
          seniority: "senior",
          reason: "titulo forte | ruby on rails | remoto",
          exclusion_reason: nil,
          score: 96,
          published_at: Time.zone.parse("2026-06-04"),
          posted_text: "publicada em 04/06/2026",
          stack_tags: %w[ruby ruby on rails],
          payload: { sample: true }
        },
        {
          classification: "rejected",
          title: "Vaga afirmativa para mulheres React",
          company_name: "Example",
          apply_url: "https://example.com/jobs/1",
          canonical_url: "https://example.com/jobs/1",
          source_url: "https://example.com/jobs/1",
          external_job_id: "1",
          fingerprint: "example::vaga afirmativa para mulheres react::example.com::1",
          remote_text: "Remoto Brasil",
          location_text: "Brasil",
          seniority: "senior",
          reason: "vaga afirmativa para mulheres",
          exclusion_reason: "vaga afirmativa para mulheres",
          score: 0,
          published_at: nil,
          posted_text: "sem data publica",
          stack_tags: [ "react" ],
          payload: { sample: false }
        }
      ]
    end
  end

  class FakeRegistry
    def supports?(adapter_key)
      adapter_key == "fake_adapter"
    end

    def fetch(_adapter_key)
      FakeAdapter
    end
  end

  class FailingAdapter
    def scan(source_scan:, window_days:)
      raise "adapter failure for #{source_scan.job_source.name} in #{window_days}d"
    end
  end

  class MixedRegistry
    def supports?(adapter_key)
      %w[fake_adapter failing_adapter].include?(adapter_key)
    end

    def fetch(adapter_key)
      case adapter_key
      when "fake_adapter"
        FakeAdapter
      when "failing_adapter"
        FailingAdapter
      else
        raise "unknown adapter #{adapter_key}"
      end
    end
  end

  test "creates search runs source scans discovered jobs and imports accepted jobs" do
    source = JobSource.create!(
      name: "Fake Source",
      slug: "fake-source",
      host: "example.com",
      base_url: "https://example.com",
      source_kind: :platform,
      adapter_key: "fake_adapter",
      supports_backfill: true,
      scan_window_days: 20
    )

    result = JobDiscovery::Orchestrator.new(
      window_days: 20,
      source_scope: JobSource.where(id: source.id),
      registry: FakeRegistry.new
    ).call

    assert result.success?
    assert_predicate result.search_run, :status_succeeded?
    assert_equal 1, result.search_run.source_scans.count
    assert_equal 2, result.search_run.discovered_jobs.count
    assert_equal 1, Job.where(company_name: "Clicksign").count
    assert_equal 1, result.search_run.search_run_items.where(outcome: :created).count
    assert_equal 1, result.search_run.search_run_items.where(outcome: :rejected).count
  end

  test "marks run partial when at least one source scan fails after importing matches" do
    good_source = JobSource.create!(
      name: "Good Source",
      slug: "good-source",
      host: "good.example.com",
      base_url: "https://good.example.com",
      source_kind: :platform,
      adapter_key: "fake_adapter",
      supports_backfill: true,
      scan_window_days: 20
    )
    bad_source = JobSource.create!(
      name: "Bad Source",
      slug: "bad-source",
      host: "bad.example.com",
      base_url: "https://bad.example.com",
      source_kind: :platform,
      adapter_key: "failing_adapter",
      supports_backfill: true,
      scan_window_days: 20
    )

    result = JobDiscovery::Orchestrator.new(
      window_days: 20,
      source_scope: JobSource.where(id: [ good_source.id, bad_source.id ]),
      registry: MixedRegistry.new
    ).call

    refute result.success?
    assert_predicate result.search_run, :status_partial?
    assert_equal 1, result.search_run.source_scans.status_failed.count
    assert_equal 1, result.search_run.search_run_items.where(outcome: :created).count
    assert_equal [ "Bad Source: adapter failure for Bad Source in 20d" ], result.errors
  end

  test "marks run failed when every source scan fails and nothing is imported" do
    source = JobSource.create!(
      name: "Bad Source",
      slug: "bad-source",
      host: "bad.example.com",
      base_url: "https://bad.example.com",
      source_kind: :platform,
      adapter_key: "failing_adapter",
      supports_backfill: true,
      scan_window_days: 20
    )

    result = JobDiscovery::Orchestrator.new(
      window_days: 20,
      source_scope: JobSource.where(id: source.id),
      registry: MixedRegistry.new
    ).call

    assert_predicate result.search_run, :status_failed?
    assert_empty result.search_run.search_run_items
    assert_equal [ "Bad Source: adapter failure for Bad Source in 20d" ], result.errors
  end
end
