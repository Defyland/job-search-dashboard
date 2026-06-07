require "test_helper"

class DiscoverJobsRunJobTest < ActiveJob::TestCase
  test "creates a cron search run with the requested window" do
    assert_difference("SearchRun.count", 1) do
      DiscoverJobsRunJob.perform_now(window_days: 1, trigger_source: "cron")
    end

    search_run = SearchRun.order(:created_at).last

    assert_equal "cron", search_run.trigger_source
    assert_equal "1d", search_run.window_label
  end

  test "skips profile scoped run when the profile no longer exists" do
    assert_no_difference("SearchRun.count") do
      DiscoverJobsRunJob.perform_now(window_days: 20, trigger_source: "manual", search_profile_id: -1)
    end
  end
end
