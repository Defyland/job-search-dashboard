require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "should get index" do
    get sources_path
    assert_response :success
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
        settings_json: JSON.dump({ "company_slugs" => [ "clicksign", "fcamara" ], "max_pages" => 3 })
      }
    }

    assert_redirected_to sources_path

    job_sources(:gupy).reload
    assert_equal 15, job_sources(:gupy).priority
    assert_equal 14, job_sources(:gupy).scan_window_days
    assert_equal [ "clicksign", "fcamara" ], job_sources(:gupy).settings["company_slugs"]
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
