require "test_helper"

class JobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "should get index" do
    get jobs_path
    assert_response :success
    assert_match("Radar de vagas", response.body)
    assert_match("Idioma", response.body)
  end

  test "should get show" do
    get job_path(jobs(:react_role))
    assert_response :success
    assert_match("Frontend Engineer Senior", response.body)
  end

  test "marks job as applied" do
    patch mark_job_path(jobs(:react_role), search_profile_id: search_profiles(:default).id, user_state: :applied)

    assert_redirected_to job_path(jobs(:react_role), search_profile_id: search_profiles(:default).id)
    assert_equal("applied", job_matches(:react_default).reload.user_state)
  end
end
