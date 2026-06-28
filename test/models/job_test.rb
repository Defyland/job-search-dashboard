require "test_helper"

class JobTest < ActiveSupport::TestCase
  test "normalizes urls" do
    job = jobs(:react_role)
    job.apply_url = "https://example.com/"
    job.canonical_url = "https://example.com/path/"
    job.save!

    assert_equal("https://example.com", job.apply_url)
    assert_equal("https://example.com/path", job.canonical_url)
  end

  test "safe apply url keeps regular http urls" do
    job = jobs(:react_role)
    job.apply_url = "https://example.com/jobs/123"

    assert_equal "https://example.com/jobs/123", job.safe_apply_url
  end

  test "safe apply url rejects invalid or unsafe schemes" do
    job = jobs(:react_role)

    job.apply_url = "javascript:alert(1)"
    assert_nil job.safe_apply_url

    job.apply_url = "data:text/html;base64,abcd"
    assert_nil job.safe_apply_url

    job.apply_url = "not a url"
    assert_nil job.safe_apply_url
  end

  test "safe canonical url only keeps http urls" do
    job = jobs(:react_role)
    job.canonical_url = "https://example.com/jobs/123"
    assert_equal "https://example.com/jobs/123", job.safe_canonical_url

    job.canonical_url = "javascript:alert(1)"
    assert_nil job.safe_canonical_url

    job.canonical_url = "not a url"
    assert_nil job.safe_canonical_url
  end

  test "infers contract type from raw payload" do
    job = jobs(:react_role)
    job.raw_payload = { employmentType: "contractor" }
    job.save!

    assert_predicate job.reload, :contract_type_pj?
  end
end
