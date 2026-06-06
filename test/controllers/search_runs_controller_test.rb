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

  test "create enqueues a rails backfill" do
    assert_enqueued_with(job: DiscoverJobsRunJob, args: [ { window_days: 20 } ]) do
      post search_runs_path, params: { window_days: 20 }
    end

    assert_redirected_to search_runs_path
  end
end
