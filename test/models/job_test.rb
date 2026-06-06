require "test_helper"

class JobTest < ActiveSupport::TestCase
  test "normalizes stack tags and urls" do
    job = jobs(:react_role)
    job.stack_tags = [ " React ", "react", "TypeScript" ]
    job.apply_url = "https://example.com/"
    job.canonical_url = "https://example.com/path/"
    job.save!

    assert_equal(%w[react typescript], job.reload.stack_tags)
    assert_equal("https://example.com", job.apply_url)
    assert_equal("https://example.com/path", job.canonical_url)
  end
end
