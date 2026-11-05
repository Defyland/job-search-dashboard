require "test_helper"

class JobsHelperTest < ActionView::TestCase
  test "radar_seen_label shows the capture timestamp used by newest sorting" do
    match = JobMatch.new(first_seen_at: Time.zone.parse("2026-06-23 08:35:27"))

    assert_equal "Capturada em 23/06 08:35", radar_seen_label(match)
  end

  test "publication_signal_label prefers stable published timestamp over stale relative text" do
    job = Job.new(
      posted_text: "Ha 1 hora",
      published_at: Time.zone.parse("2026-06-21 11:08:29")
    )

    assert_equal "Publicada em 21/06 11:08", publication_signal_label(job)
  end

  test "advanced_filter_count ignores search, state, market and profile params" do
    assert_equal 0, advanced_filter_count({ q: "Rails", user_state: "seen", market: "national", search_profile_id: "1" })
  end

  test "advanced_filter_count ignores defaults of the advanced controls" do
    filters = { contract_type: "all", match_strength: "all", title_language: "all", lifecycle_state: "active", sort: "newest", recency: "", source: "", stack: "" }

    assert_equal 0, advanced_filter_count(filters)
    assert_equal 0, advanced_filter_count({})
  end

  test "advanced_filter_count counts each advanced control that departs from its default" do
    filters = { stack: "ruby", contract_type: "clt", lifecycle_state: "all", sort: "newest", q: "Rails" }

    assert_equal 3, advanced_filter_count(filters)
    assert_equal 1, advanced_filter_count({ recency: "7d" })
  end
end
