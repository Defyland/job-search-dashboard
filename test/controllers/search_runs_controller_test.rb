require "test_helper"

class SearchRunsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as(users(:one))
  end

  test "should get index" do
    get search_runs_path
    assert_response :success
  end

  test "should get show" do
    get search_run_path(search_runs(:recent))
    assert_response :success
    assert_match("Run ##{search_runs(:recent).id}", response.body)
  end

  test "show renders source scan errors for failed adapters" do
    source_scan = SourceScan.create!(
      search_run: search_runs(:older),
      job_source: job_sources(:gupy),
      status: :failed,
      pages_scanned: 0,
      candidates_seen: 0,
      accepted_count: 0,
      borderline_count: 0,
      rejected_count: 0,
      expired_count: 0,
      error_message: "request failed: https://programathor.com.br/jobs-city/remoto?expertise=S%C3%AAnior -> 403",
      started_at: 5.days.ago,
      finished_at: 5.days.ago + 10.seconds
    )

    get search_run_path(source_scan.search_run)

    assert_response :success
    assert_match("Detalhe", response.body)
    assert_match("request failed: https://programathor.com.br/jobs-city/remoto?expertise=S%C3%AAnior -&gt; 403", response.body)
  end

  test "create enqueues a rails backfill" do
    assert_enqueued_with(job: DiscoverJobsRunJob, args: [ { window_days: 20, trigger_source: :manual, source_slug: nil } ]) do
      post search_runs_path, params: { window_days: 20 }
    end

    assert_redirected_to search_runs_path
  end

  test "create clamps manual backfill to the profile scan window ceiling" do
    assert_enqueued_with(job: DiscoverJobsRunJob, args: [ { window_days: 60, trigger_source: :manual, source_slug: nil } ]) do
      post search_runs_path, params: { window_days: 90 }
    end

    assert_redirected_to search_runs_path
  end

  test "create enqueues a source-scoped rails backfill" do
    source = JobSource.create!(
      name: "Scoped Source",
      slug: "scoped-source",
      host: "scoped.example.com",
      base_url: "https://scoped.example.com",
      source_kind: :platform,
      adapter_key: "gupy_company_boards",
      enabled: true,
      supports_backfill: true,
      scan_window_days: 14
    )

    assert_enqueued_with(job: DiscoverJobsRunJob, args: [ { window_days: 14, trigger_source: :manual, source_slug: source.slug } ]) do
      post search_runs_path, params: { window_days: 14, source_slug: source.slug }
    end

    assert_redirected_to search_runs_path
  end

  test "create rejects an invalid source slug" do
    assert_no_enqueued_jobs only: DiscoverJobsRunJob do
      post search_runs_path, params: { window_days: 20, source_slug: "missing-source" }
    end

    assert_redirected_to search_runs_path
  end
end
