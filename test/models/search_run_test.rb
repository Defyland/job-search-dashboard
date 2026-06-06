require "test_helper"

class SearchRunTest < ActiveSupport::TestCase
  test "calculates duration in seconds" do
    assert_equal 3600, search_runs(:recent).duration_seconds
  end
end
