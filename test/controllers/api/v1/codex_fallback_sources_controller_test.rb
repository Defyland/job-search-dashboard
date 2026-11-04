require "test_helper"

class Api::V1::CodexFallbackSourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_token = ENV["INGEST_SHARED_TOKEN"]
    ENV["INGEST_SHARED_TOKEN"] = "secret-token"
  end

  teardown do
    ENV["INGEST_SHARED_TOKEN"] = @previous_token
  end

  test "returns enabled codex fallback sources with policy guidance" do
    previous_token = ENV["INGEST_SHARED_TOKEN"]
    previous_search_key = ENV["SEARCH_INDEX_API_KEY"]
    previous_serpapi_key = ENV["SERPAPI_API_KEY"]
    ENV["INGEST_SHARED_TOKEN"] = "secret-token"
    ENV["SEARCH_INDEX_API_KEY"] = nil
    ENV["SERPAPI_API_KEY"] = nil
    JobSources::Catalog.seed!

    get api_v1_codex_fallback_sources_path,
        headers: { "Authorization" => "Bearer secret-token" },
        as: :json

    assert_response :success

    body = response.parsed_body
    slugs = body.fetch("sources").map { |source| source.fetch("slug") }

    assert_includes slugs, "apinfo"
    assert_includes slugs, "bamboohr"
    assert_includes slugs, "get-great-careers"
    assert_includes slugs, "icims"
    assert_includes slugs, "indeed"
    assert_includes slugs, "jazzhr"
    assert_includes slugs, "jobvite"
    assert_includes slugs, "landor-ats"
    assert_includes slugs, "linkedin"
    assert_includes slugs, "netvagas"
    assert_includes slugs, "remotely-works"
    assert_includes slugs, "rubyonremote"
    assert_includes slugs, "workday"
    assert_includes slugs, "itjobs-pt"
    assert_includes slugs, "teamlyzer-jobs"
    assert_includes slugs, "landing-jobs"
    assert_includes slugs, "englishjobs-pt"
    assert_includes slugs, "net-empregos-pt"
    assert_includes slugs, "sapo-emprego"
    assert_includes slugs, "eurotechjobs"
    assert_includes slugs, "hays-portugal"
    assert_includes slugs, "turnkey-staffing"
    assert_includes slugs, "clouddevs"
    assert_includes slugs, "hire-with-near"
    assert_includes slugs, "weknow"
    assert_includes slugs, "revelo"
    assert_includes slugs, "awana"
    assert_includes slugs, "tecla"
    assert_includes slugs, "vanhack"
    assert_equal "/api/v1/job_ingestions", body.fetch("ingestion_endpoint")
    assert_equal false, body.dig("search_index", "rails_native_enabled")
    query_text = body.dig("search_index", "queries").map { |query| query.fetch("query") }.join("\n")

    assert_includes query_text, "site:jobs.ashbyhq.com"
    assert_includes query_text, "site:br.indeed.com"
    assert_includes query_text, "site:pt.indeed.com"
    assert_includes query_text, "site:www.itjobs.pt"
    assert_includes query_text, "site:pt.teamlyzer.com/companies/jobs"
    assert_includes query_text, "site:www.hays.pt"
    assert_includes query_text, "site:turnkeystaffing.com/career"
    assert_includes query_text, "site:clouddevs.com/jobs"
    assert_includes query_text, "site:jobs.hirewithnear.com"
    assert_includes query_text, "site:weknowinc.com/careers/work-at-weknow"
    assert_includes query_text, "site:careers.revelo.com"
    assert_includes query_text, "site:www.awana.io/job-openings.html"
    assert_includes query_text, "site:www.tecla.io/join"
    assert_includes query_text, "site:vanhack.com/get-hired"
    default_policy = body.dig("policy", "profiles").find { |profile| profile.fetch("profile_name").include?("Ruby/Rails") }
    inclusive_policy = body.dig("policy", "profiles").find { |profile| profile.fetch("profile_name").include?("afirmativas") }

    assert_includes default_policy.fetch("stack_terms"), "ruby on rails"
    assert_includes default_policy.fetch("exclude_terms"), "mulheres"
    assert_equal "both", default_policy.fetch("language_scope")
    assert_not_includes inclusive_policy.fetch("exclude_terms"), "women only"
  ensure
    ENV["INGEST_SHARED_TOKEN"] = previous_token
    ENV["SEARCH_INDEX_API_KEY"] = previous_search_key
    ENV["SERPAPI_API_KEY"] = previous_serpapi_key
  end

  test "rejects requests without ingestion token" do
    previous_token = ENV["INGEST_SHARED_TOKEN"]
    ENV["INGEST_SHARED_TOKEN"] = "secret-token"

    get api_v1_codex_fallback_sources_path, as: :json

    assert_response :unauthorized
    assert_equal({ "error" => "invalid_ingest_token" }, response.parsed_body)
  ensure
    ENV["INGEST_SHARED_TOKEN"] = previous_token
  end

  test "coverage lists native backfill sources with only the board identifiers the query contract allows" do
    greenhouse = create_native_greenhouse
    JobSource.create!(
      name: "Ashby",
      slug: "ashby",
      source_kind: :ats,
      base_url: "https://jobs.ashbyhq.com",
      host: "jobs.ashbyhq.com",
      priority: 10,
      adapter_key: "ashby_job_board",
      supports_backfill: true,
      settings: { board_slugs: [ "zeta", "alpha" ] }
    )
    JobSource.create!(
      name: "Ashby Off",
      slug: "ashby-off",
      host: "off.example.com",
      priority: 1,
      enabled: false,
      adapter_key: "ashby_job_board",
      supports_backfill: true,
      settings: { board_slugs: [ "disabled" ] }
    )
    JobSource.create!(
      name: "Codex Only",
      slug: "codex-only",
      host: "codex-only.example.com",
      priority: 1,
      adapter_key: "manual_only",
      codex_fallback_enabled: true,
      codex_fallback_reason: "manual review",
      settings: { company_slugs: [ "codex-only" ] }
    )

    get api_v1_codex_fallback_sources_path, headers: authorization_headers, as: :json

    assert_response :success
    assert_equal [
      { "slug" => "ashby", "host" => "jobs.ashbyhq.com", "last_full_scan_at" => nil, "known_boards" => { "board_slugs" => %w[alpha zeta] } },
      { "slug" => "greenhouse", "host" => "job-boards.greenhouse.io", "last_full_scan_at" => greenhouse.last_full_scan_at.iso8601, "known_boards" => { "board_tokens" => %w[acme globex] } }
    ], response.parsed_body.fetch("coverage").fetch("native_sources")
    refute_includes response.body, "SENTINEL-SECRET"
    refute_includes response.body, %("disabled")
  end

  test "coverage reports the latest completed codex run by finish time and hides run internals" do
    SearchRun.trigger_source_codex_automation.destroy_all
    older = SearchRun.create!(
      trigger_source: :codex_automation,
      status: :succeeded,
      window_label: "7d",
      started_at: 3.days.ago,
      finished_at: 3.days.ago + 5.minutes,
      client_run_id: "client-sentinel",
      request_digest: "digest-sentinel",
      summary: { email: "leak@example.com", jobs: [ { title: "raw-job-sentinel" } ] }
    )
    SearchRun.create!(
      trigger_source: :codex_automation,
      status: :failed,
      window_label: "24h",
      started_at: 1.hour.ago,
      finished_at: 50.minutes.ago,
      error_message: "error-sentinel",
      summary: { errors: [ "error-sentinel" ] }
    )
    SearchRun.create!(trigger_source: :codex_automation, status: :running, window_label: "24h", started_at: 30.minutes.ago)
    SearchRun.create!(
      trigger_source: :manual,
      status: :succeeded,
      window_label: "24h",
      started_at: 10.minutes.ago,
      finished_at: 5.minutes.ago
    )

    get api_v1_codex_fallback_sources_path, headers: authorization_headers, as: :json

    assert_response :success
    assert_equal coverage_run_payload(older), response.parsed_body.fetch("coverage").fetch("last_successful_codex_run")
    %w[leak@example.com raw-job-sentinel client-sentinel digest-sentinel error-sentinel].each do |sentinel|
      refute_includes response.body, sentinel
    end

    partial = SearchRun.create!(
      trigger_source: :codex_automation,
      status: :partial,
      window_label: "24h",
      started_at: 4.days.ago,
      finished_at: 2.days.ago
    )

    get api_v1_codex_fallback_sources_path, headers: authorization_headers, as: :json

    assert_response :success
    assert_equal coverage_run_payload(partial), response.parsed_body.fetch("coverage").fetch("last_successful_codex_run")
  end

  test "coverage is empty when no source is enabled and no codex run completed" do
    JobSource.update_all(enabled: false)
    SearchRun.trigger_source_codex_automation.destroy_all

    get api_v1_codex_fallback_sources_path, headers: authorization_headers, as: :json

    assert_response :success
    assert_equal(
      { "native_sources" => [], "last_successful_codex_run" => nil },
      response.parsed_body.fetch("coverage")
    )
  end

  test "coverage request is read only" do
    create_native_greenhouse
    sources_before = JobSource.order(:id).pluck(:id, :updated_at, :settings)

    assert_no_difference([ "Job.count", "SearchRun.count", "SourceScan.count" ]) do
      get api_v1_codex_fallback_sources_path, headers: authorization_headers, as: :json
    end

    assert_response :success
    assert_equal sources_before, JobSource.order(:id).pluck(:id, :updated_at, :settings)
  end

  private
    def authorization_headers
      { "Authorization" => "Bearer secret-token" }
    end

    def create_native_greenhouse
      JobSource.create!(
        name: "Greenhouse",
        slug: "greenhouse",
        source_kind: :ats,
        base_url: "https://job-boards.greenhouse.io",
        host: "job-boards.greenhouse.io",
        priority: 20,
        adapter_key: "greenhouse_boards_api",
        supports_backfill: true,
        codex_fallback_enabled: false,
        last_full_scan_at: Time.zone.parse("2026-11-01 10:00:00"),
        settings: {
          board_tokens: [ " acme ", "acme", "", "globex" ],
          max_pages: 5,
          api_key: "SENTINEL-SECRET",
          region: "br"
        }
      )
    end

    def coverage_run_payload(run)
      {
        "id" => run.id,
        "status" => run.status,
        "started_at" => run.started_at.iso8601,
        "finished_at" => run.finished_at.iso8601,
        "window_label" => run.window_label
      }
    end
end
