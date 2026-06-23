require "test_helper"

class JobDiscovery::SearchIndex::UrlClassifierTest < ActiveSupport::TestCase
  test "extracts adapter settings from supported ats urls" do
    classifier = JobDiscovery::SearchIndex::UrlClassifier.new

    assert_discovery classifier.call("https://jobs.ashbyhq.com/acme/123"), "ashby", "board_slugs", "acme"
    assert_discovery classifier.call("https://job-boards.greenhouse.io/acme/jobs/123"), "greenhouse", "board_tokens", "acme"
    assert_discovery classifier.call("https://boards.greenhouse.io/acme/jobs/123"), "greenhouse", "board_tokens", "acme"
    assert_discovery classifier.call("https://jobs.lever.co/acme/123"), "lever", "company_slugs", "acme"
    assert_discovery classifier.call("https://jobs.smartrecruiters.com/Acme/123-dev"), "smartrecruiters", "company_identifiers", "Acme"
    assert_discovery classifier.call("https://jobs.quickin.io/evtit/jobs/abc"), "quickin", "company_slugs", "evtit"
  end

  test "ignores unsupported urls" do
    classifier = JobDiscovery::SearchIndex::UrlClassifier.new

    assert_nil classifier.call("https://www.linkedin.com/jobs/view/123")
    assert_nil classifier.call("not a url")
  end

  private
    def assert_discovery(discovery, source_slug, setting_key, setting_value)
      assert_equal source_slug, discovery.source_slug
      assert_equal setting_key, discovery.setting_key
      assert_equal setting_value, discovery.setting_value
    end
end
