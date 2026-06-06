require "test_helper"

class ExpireStaleJobsJobTest < ActiveJob::TestCase
  test "expires active jobs that have not been seen recently" do
    jobs(:react_role).update!(last_seen_at: 30.days.ago)

    ExpireStaleJobsJob.perform_now

    assert_equal "expired", jobs(:react_role).reload.lifecycle_state
  end
end
