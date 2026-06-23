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
end
