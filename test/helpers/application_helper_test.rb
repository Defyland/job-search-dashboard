require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "safe_external_url keeps regular http urls" do
    assert_equal "https://example.com/jobs/123", safe_external_url("https://example.com/jobs/123")
  end

  test "safe_external_url rejects invalid or unsafe schemes" do
    assert_nil safe_external_url("javascript:alert(1)")
    assert_nil safe_external_url("data:text/html;base64,abcd")
    assert_nil safe_external_url("not a url")
  end
end
