require "test_helper"

class JobDiscovery::OrchestratorTest < ActiveSupport::TestCase
  class FakeAdapter
    def initialize(**)
    end

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
      adapter_key == "gupy_company_boards"
    end

    def fetch(_adapter_key)
      FakeAdapter
    end
  end

  class FailingAdapter
    def initialize(**)
    end

    def scan(source_scan:, window_days:)
      raise "adapter failure for #{source_scan.job_source.name} in #{window_days}d"
    end
  end

  class TransactionProbeAdapter
    class_attribute :open_transactions_during_scan, default: nil

    def initialize(**)
    end

    def scan(source_scan:, window_days:)
      self.class.open_transactions_during_scan = ActiveRecord::Base.connection.open_transactions
      []
    end
  end

  class ScopedPolicyAdapter
    def initialize(policy:)
      @policy = policy
    end

    def scan(source_scan:, window_days:)
      decision = @policy.classify(
        title: "Senior Ruby on Rails Engineer",
        remote_text: "Remoto Brasil",
        location_text: "Brasil",
        description: "Ruby on Rails remoto",
        source_slug: source_scan.job_source.slug,
        posted_text: "publicada em 04/06/2026",
        published_at: Time.zone.parse("2026-06-04")
      )

      [
        {
          classification: decision.classification.to_s,
          title: "Senior Ruby on Rails Engineer",
          company_name: "Clicksign",
          apply_url: "https://clicksign.gupy.io/candidates/jobs/11234166/apply",
          canonical_url: "https://clicksign.gupy.io/jobs/11234166",
          source_url: "https://clicksign.gupy.io/jobs/11234166",
          external_job_id: "11234166",
          fingerprint: "clicksign::senior ruby on rails engineer::clicksign.gupy.io::11234166",
          remote_text: "Remoto Brasil",
          location_text: "Brasil",
          seniority: decision.seniority,
          reason: decision.reason,
          exclusion_reason: decision.exclusion_reason,
          score: decision.score,
          published_at: Time.zone.parse("2026-06-04"),
          posted_text: "publicada em 04/06/2026",
          stack_tags: decision.stack_tags,
          payload: { sample: true }
        }
      ]
    end
  end

  class MixedRegistry
    def supports?(adapter_key)
      %w[gupy_company_boards lever_company_boards].include?(adapter_key)
    end

    def fetch(adapter_key)
      case adapter_key
      when "gupy_company_boards"
        FakeAdapter
      when "lever_company_boards"
        FailingAdapter
      else
        raise "unknown adapter #{adapter_key}"
      end
    end
  end

  class TransactionProbeRegistry
    def supports?(adapter_key)
      adapter_key == "gupy_company_boards"
    end

    def fetch(_adapter_key)
      TransactionProbeAdapter
    end
  end

  class ScopedPolicyRegistry
    def supports?(adapter_key)
      adapter_key == "gupy_company_boards"
    end

    def fetch(_adapter_key)
      ScopedPolicyAdapter
    end
  end

  # Only the external HTTP fetcher is faked; the real Remotive adapter, Recorder and database run.
  class ScriptedFetcher
    def initialize(*responses)
      @responses = responses
    end

    def call(_url, **)
      response = @responses.shift
      raise response if response.is_a?(Exception)

      response
    end
  end

  class RemotiveAdapterFactory
    def initialize(fetcher:)
      @fetcher = fetcher
    end

    def new(policy:)
      JobDiscovery::Adapters::RemotiveRemoteJobsAdapter.new(fetcher: @fetcher, policy:)
    end
  end

  class RemotiveRegistry
    def initialize(fetcher:)
      @fetcher = fetcher
    end

    def supports?(adapter_key)
      adapter_key == "remotive_remote_jobs"
    end

    def fetch(_adapter_key)
      RemotiveAdapterFactory.new(fetcher: @fetcher)
    end
  end

  # Records the window each source is scanned with and finds nothing, so only the window is observed.
  class WindowProbeAdapter
    class_attribute :received_windows, default: {}

    def initialize(**)
    end

    def scan(source_scan:, window_days:)
      self.class.received_windows[source_scan.job_source.slug] = window_days
      []
    end
  end

  class WindowProbeRegistry
    def supports?(adapter_key)
      adapter_key == "window_probe"
    end

    def fetch(_adapter_key)
      WindowProbeAdapter
    end
  end

  # Isolates the external SERP-backed search index seeder; the orchestrator itself is not faked.
  class NoopSearchIndexSeeder
    def initialize(**)
    end

    def call
      {}
    end
  end

  test "creates search runs source scans discovered jobs and imports accepted jobs" do
    source = JobSource.create!(
      name: "Fake Source",
      slug: "fake-source",
      host: "example.com",
      base_url: "https://example.com",
      source_kind: :platform,
      adapter_key: "gupy_company_boards",
      supports_backfill: false,
      scan_window_days: 20
    )
    source.update_columns(supports_backfill: true)

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

    clicksign_job = Job.find_by!(company_name: "Clicksign")
    accepted_candidate = result.search_run.discovered_jobs.find_by!(company_name: "Clicksign")
    rejected_candidate = result.search_run.discovered_jobs.find_by!(company_name: "Example")
    assert_equal clicksign_job.id, accepted_candidate.job_id, "accepted candidate must be linked to its canonical job"
    assert_nil rejected_candidate.job_id, "rejected candidate has no canonical job to link"
  end

  test "marks run partial when at least one source scan fails after importing matches" do
    good_source = JobSource.create!(
      name: "Good Source",
      slug: "good-source",
      host: "good.example.com",
      base_url: "https://good.example.com",
      source_kind: :platform,
      adapter_key: "gupy_company_boards",
      supports_backfill: false,
      scan_window_days: 20
    )
    good_source.update_columns(supports_backfill: true)
    bad_source = JobSource.create!(
      name: "Bad Source",
      slug: "bad-source",
      host: "bad.example.com",
      base_url: "https://bad.example.com",
      source_kind: :platform,
      adapter_key: "lever_company_boards",
      supports_backfill: false,
      scan_window_days: 20
    )
    bad_source.update_columns(supports_backfill: true)

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
      adapter_key: "lever_company_boards",
      supports_backfill: false,
      scan_window_days: 20
    )
    source.update_columns(supports_backfill: true)

    result = JobDiscovery::Orchestrator.new(
      window_days: 20,
      source_scope: JobSource.where(id: source.id),
      registry: MixedRegistry.new
    ).call

    assert_predicate result.search_run, :status_failed?
    assert_empty result.search_run.search_run_items
    assert_equal [ "Bad Source: adapter failure for Bad Source in 20d" ], result.errors
  end

  test "marks run failed and records source scan when a backfillable source has unsupported adapter" do
    source = JobSource.create!(
      name: "Broken Source",
      slug: "broken-source",
      host: "broken.example.com",
      base_url: "https://broken.example.com",
      source_kind: :platform,
      adapter_key: "unsupported_adapter",
      supports_backfill: false,
      scan_window_days: 20
    )
    source.update_columns(supports_backfill: true)

    result = JobDiscovery::Orchestrator.new(
      window_days: 20,
      source_scope: JobSource.where(id: source.id),
      registry: FakeRegistry.new
    ).call

    assert_predicate result.search_run, :status_failed?
    assert_empty result.search_run.search_run_items
    assert_equal 1, result.search_run.source_scans.status_failed.count
    assert_equal "adapter unsupported_adapter nao suportado", result.search_run.source_scans.status_failed.first.error_message
    assert_equal [ "Broken Source: adapter unsupported_adapter nao suportado" ], result.errors
  end

  test "does not hold a database transaction while adapters scan remote sources" do
    source = JobSource.create!(
      name: "Probe Source",
      slug: "probe-source",
      host: "probe.example.com",
      base_url: "https://probe.example.com",
      source_kind: :platform,
      adapter_key: "gupy_company_boards",
      supports_backfill: false,
      scan_window_days: 20
    )
    source.update_columns(supports_backfill: true)
    open_transactions_before_scan = ActiveRecord::Base.connection.open_transactions

    result = JobDiscovery::Orchestrator.new(
      window_days: 20,
      source_scope: JobSource.where(id: source.id),
      registry: TransactionProbeRegistry.new
    ).call

    assert result.success?
    assert_equal open_transactions_before_scan, TransactionProbeAdapter.open_transactions_during_scan
    assert_predicate result.search_run.source_scans.first, :status_exhausted?
  end

  test "supports profile-scoped discovery runs" do
    source = JobSource.create!(
      name: "Scoped Source",
      slug: "scoped-source",
      host: "scoped.example.com",
      base_url: "https://scoped.example.com",
      source_kind: :platform,
      adapter_key: "gupy_company_boards",
      supports_backfill: false,
      scan_window_days: 20
    )
    source.update_columns(supports_backfill: true)
    profile = users(:one).search_profiles.create!(
      name: "Senior Java Remote",
      slug: "senior-java-remote-orchestrator",
      active: true,
      required_remote: true,
      include_women_only: false,
      language_scope: :both,
      target_stacks: [ "java" ],
      target_titles: [ "developer", "engineer" ],
      seniority_terms: [ "senior", "sênior", "sr" ],
      location_terms: [ "remote", "remoto", "brasil", "brazil" ],
      negative_terms: SearchProfile::DEFAULT_NEGATIVE_TERMS,
      scan_window_days: 20
    )

    result = JobDiscovery::Orchestrator.new(
      window_days: 20,
      source_scope: JobSource.where(id: source.id),
      registry: ScopedPolicyRegistry.new,
      search_profiles: [ profile ]
    ).call

    assert result.success?
    assert_predicate result.search_run, :status_succeeded?
    assert_equal [ profile.id ], result.search_run.summary.fetch("search_profile_ids")
    assert_equal 0, result.search_run.search_run_items.where(outcome: :created).count
    assert_equal 1, result.search_run.search_run_items.where(outcome: :rejected).count
    assert_nil Job.find_by(canonical_url: "https://clicksign.gupy.io/jobs/11234166")
  end

  test "cron recovers the jobs missed by a failed run since the last successful full scan" do
    source = job_sources(:workable)
    source.update!(adapter_key: "remotive_remote_jobs", supports_backfill: true, settings: {}, last_full_scan_at: nil)
    fetcher = ScriptedFetcher.new(
      remotive_feed,
      RuntimeError.new("remotive unreachable"),
      remotive_feed(
        remotive_job(id: 101, company: "Initech", published_at: Time.zone.local(2026, 10, 31, 10)),
        remotive_job(id: 102, company: "Acme Labs", published_at: Time.zone.local(2026, 11, 1, 10)),
        remotive_job(id: 103, company: "Globex", published_at: Time.zone.local(2026, 11, 2, 10))
      )
    )
    registry = RemotiveRegistry.new(fetcher:)

    travel_to Time.zone.local(2026, 11, 1, 8, 30) do
      result = run_orchestrator(sources: [ source ], window_days: 1, trigger_source: :cron, registry:)

      assert result.success?
      assert_predicate result.search_run.source_scans.first, :status_exhausted?
      assert_equal Time.zone.local(2026, 11, 1, 8, 30), source.reload.last_full_scan_at
    end

    travel_to Time.zone.local(2026, 11, 2, 8, 30) do
      result = run_orchestrator(sources: [ source ], window_days: 1, trigger_source: :cron, registry:)

      refute result.success?
      assert_predicate result.search_run, :status_failed?
      assert_equal [ "Workable: remotive unreachable" ], result.errors
      assert_equal Time.zone.local(2026, 11, 1, 8, 30), source.reload.last_full_scan_at
    end

    travel_to Time.zone.local(2026, 11, 3, 8, 30) do
      result = run_orchestrator(sources: [ source ], window_days: 1, trigger_source: :cron, registry:)

      assert result.success?
      assert_predicate result.search_run, :status_succeeded?
      assert_equal [ "Acme Labs", "Globex" ], result.search_run.discovered_jobs.order(:company_name).pluck(:company_name)
      assert_equal [ "Acme Labs", "Globex" ], Job.where(company_name: [ "Acme Labs", "Globex", "Initech" ]).order(:company_name).pluck(:company_name)
      assert_equal Time.zone.local(2026, 11, 3, 8, 30), source.reload.last_full_scan_at
    end
  end

  test "cron widens the scan window to the days since the last full scan, capped at seven" do
    travel_to Time.zone.local(2026, 11, 4, 8, 30) do
      sources = [ create_probe_source("window-probe", last_full_scan_at: 10.days.ago) ]

      assert_equal({ "window-probe" => 7 }, run_probe(sources, trigger_source: :cron))
    end
  end

  test "cron keeps the requested window when no full scan has succeeded yet" do
    travel_to Time.zone.local(2026, 11, 4, 8, 30) do
      sources = [ create_probe_source("never-scanned-probe", last_full_scan_at: nil) ]

      assert_equal({ "never-scanned-probe" => 1 }, run_probe(sources, trigger_source: :cron))
    end
  end

  test "cron keeps a larger requested window when the gap since the last full scan is shorter" do
    travel_to Time.zone.local(2026, 11, 4, 8, 30) do
      sources = [ create_probe_source("requested-probe", last_full_scan_at: 1.day.ago) ]

      assert_equal({ "requested-probe" => 3 }, run_probe(sources, trigger_source: :cron, window_days: 3))
    end
  end

  test "manual and codex_automation scans keep the requested window after a gap" do
    travel_to Time.zone.local(2026, 11, 4, 8, 30) do
      manual = [ create_probe_source("manual-probe", last_full_scan_at: 2.days.ago) ]
      codex = [ create_probe_source("codex-probe", last_full_scan_at: 2.days.ago) ]

      assert_equal({ "manual-probe" => 20 }, run_probe(manual, trigger_source: :manual, window_days: 20))
      assert_equal({ "codex-probe" => 20 }, run_probe(codex, trigger_source: :codex_automation, window_days: 20))
    end
  end

  test "cron gives each source its own window from its own last full scan" do
    travel_to Time.zone.local(2026, 11, 4, 8, 30) do
      sources = [
        create_probe_source("probe-two", last_full_scan_at: 2.days.ago),
        create_probe_source("probe-five", last_full_scan_at: 5.days.ago)
      ]

      assert_equal({ "probe-two" => 2, "probe-five" => 5 }, run_probe(sources, trigger_source: :cron))
    end
  end

  test "cron trigger given as a string or a symbol recovers the same window" do
    travel_to Time.zone.local(2026, 11, 4, 8, 30) do
      as_string = [ create_probe_source("string-probe", last_full_scan_at: 5.days.ago) ]
      as_symbol = [ create_probe_source("symbol-probe", last_full_scan_at: 5.days.ago) ]

      assert_equal({ "string-probe" => 5 }, run_probe(as_string, trigger_source: "cron"))
      assert_equal({ "symbol-probe" => 5 }, run_probe(as_symbol, trigger_source: :cron))
    end
  end

  private
    def run_orchestrator(sources:, window_days:, trigger_source:, registry:)
      JobDiscovery::Orchestrator.new(
        window_days:,
        trigger_source:,
        source_scope: JobSource.where(id: sources.map(&:id)),
        registry:,
        search_index_seeder_class: NoopSearchIndexSeeder
      ).call
    end

    def run_probe(sources, trigger_source:, window_days: 1)
      WindowProbeAdapter.received_windows = {}
      result = run_orchestrator(sources:, window_days:, trigger_source:, registry: WindowProbeRegistry.new)

      assert result.success?
      WindowProbeAdapter.received_windows
    end

    def create_probe_source(slug, last_full_scan_at:)
      JobSource.create!(
        name: slug.titleize,
        slug:,
        host: "#{slug}.example.com",
        base_url: "https://#{slug}.example.com",
        source_kind: :platform,
        adapter_key: "window_probe",
        scan_window_days: 20,
        last_full_scan_at:
      )
    end

    def remotive_feed(*jobs)
      { "job-count" => jobs.size, "jobs" => jobs }.to_json
    end

    def remotive_job(id:, company:, published_at:)
      {
        "id" => id,
        "url" => "https://remotive.com/remote-jobs/backend/senior-ruby-on-rails-developer-#{id}",
        "title" => "Senior Ruby on Rails Developer",
        "company_name" => company,
        "category" => "Software Development",
        "tags" => %w[ruby rails],
        "job_type" => "full_time",
        "publication_date" => published_at.iso8601,
        "candidate_required_location" => "Worldwide",
        "description" => "<p>Remote Ruby on Rails role.</p>"
      }
    end
end
