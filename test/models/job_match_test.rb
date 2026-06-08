require "test_helper"

class JobMatchTest < ActiveSupport::TestCase
  test "keeps user state per profile" do
    match = job_matches(:react_default)

    match.update!(user_state: :applied)

    assert_equal "applied", match.reload.user_state
  end
end
