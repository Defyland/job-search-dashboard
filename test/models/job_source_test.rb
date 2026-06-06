require "test_helper"

class JobSourceTest < ActiveSupport::TestCase
  test "seeds the default catalog idempotently" do
    missing_sources = JobSource::DEFAULT_CATALOG.count - JobSource.count

    assert_difference("JobSource.count", missing_sources) do
      JobSource.seed_defaults!
    end

    assert_no_difference("JobSource.count") do
      JobSource.seed_defaults!
    end
  end
end
