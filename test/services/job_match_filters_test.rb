require "test_helper"

class JobMatchFiltersTest < ActiveSupport::TestCase
  test "filters matches by profile scoped stack and user state" do
    filtered = JobMatchFilters.new(
      scope: JobMatch.for_profile(search_profiles(:default)).includes(job: :job_source),
      params: { stack: "react", user_state: "new_match", lifecycle_state: "active" }
    ).call

    assert_equal [ job_matches(:react_default) ], filtered.to_a
  end
end
