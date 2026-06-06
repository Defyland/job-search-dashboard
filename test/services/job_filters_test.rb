require "test_helper"

class JobFiltersTest < ActiveSupport::TestCase
  test "filters by stack and user state" do
    filtered = JobFilters.new(
      scope: Job.includes(:job_source),
      params: { stack: "react", user_state: "new_match", lifecycle_state: "active" }
    ).call

    assert_equal [ jobs(:react_role) ], filtered.to_a
  end
end
