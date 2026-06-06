require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "should get index" do
    get sources_path
    assert_response :success
  end

  test "index renders latest scan coverage for each source" do
    source_scan = SourceScan.create!(
      search_run: search_runs(:recent),
      job_source: job_sources(:gupy),
      status: :succeeded,
      pages_scanned: 4,
      candidates_seen: 12,
      accepted_count: 3,
      borderline_count: 1,
      rejected_count: 8,
      expired_count: 0,
      started_at: 2.hours.ago,
      finished_at: 2.hours.ago + 3.minutes
    )

    get sources_path

    assert_response :success
    assert_match("Run ##{source_scan.search_run_id}", response.body)
    assert_match("Paginas:", response.body)
    assert_match("Paginas:</span> 4", response.body)
    assert_match("Candidatos:", response.body)
    assert_match("Candidatos:</span> 12", response.body)
  end

  test "should get edit" do
    get edit_source_path(job_sources(:gupy))
    assert_response :success
  end

  test "should update source with valid settings json" do
    patch source_path(job_sources(:gupy)), params: {
      job_source: {
        name: "Gupy",
        base_url: "https://gupy.io",
        host: "gupy.io",
        adapter_key: "gupy_company_boards",
        priority: 15,
        scan_window_days: 14,
        enabled: "1",
        supports_backfill: "1",
        settings_json: JSON.dump({ "board_urls" => [ "https://clicksign.gupy.io/", "https://memed.gupy.io/" ], "max_pages" => 3 })
      }
    }

    assert_redirected_to sources_path

    job_sources(:gupy).reload
    assert_equal 15, job_sources(:gupy).priority
    assert_equal 14, job_sources(:gupy).scan_window_days
    assert_equal [ "https://clicksign.gupy.io/", "https://memed.gupy.io/" ], job_sources(:gupy).settings["board_urls"]
    assert_equal 3, job_sources(:gupy).settings["max_pages"]
  end

  test "should reject invalid settings json" do
    patch source_path(job_sources(:gupy)), params: {
      job_source: {
        name: "Gupy",
        base_url: "https://gupy.io",
        host: "gupy.io",
        adapter_key: "gupy_company_boards",
        priority: 10,
        scan_window_days: 20,
        enabled: "1",
        supports_backfill: "1",
        settings_json: "{invalid"
      }
    }

    assert_response :unprocessable_entity
    assert_match("JSON inv", response.body)
  end
end
