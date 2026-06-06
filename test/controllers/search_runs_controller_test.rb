require "test_helper"

class SearchRunsControllerTest < ActionDispatch::IntegrationTest
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
end
