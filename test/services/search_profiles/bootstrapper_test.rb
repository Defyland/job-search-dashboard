require "test_helper"

module SearchProfiles
  class BootstrapperTest < ActiveSupport::TestCase
    test "backfills matching active jobs for a new profile" do
      job = Job.create!(
        job_source: job_sources(:gupy),
        title: "Senior React Engineer",
        company_name: "Nova",
        apply_url: "https://nova.gupy.io/jobs/react-1",
        canonical_url: "https://nova.gupy.io/jobs/react-1",
        source_url: "https://nova.gupy.io/jobs/react-1",
        ats_name: "Gupy",
        external_job_id: "react-1",
        remote_text: "Remoto Brasil",
        location_text: "Brasil",
        seniority: "senior",
        match_strength: :strong,
        user_state: :new_match,
        lifecycle_state: :active,
        reason: "Titulo senior com stack React e remoto BR.",
        score: 96,
        posted_text: "publicada ha 1 dia",
        published_at: 1.day.ago,
        first_seen_at: 1.day.ago,
        last_seen_at: 1.day.ago,
        last_validated_at: 1.day.ago,
        fingerprint: "nova::senior react engineer::gupy.io::react-1",
        stack_tags: [ "react" ],
        raw_payload: {
          title: "Senior React Engineer",
          company: "Nova",
          description: "React, TypeScript, remote Brazil"
        }
      )

      profile = users(:one).search_profiles.create!(
        name: "Senior React Remote BR",
        slug: "senior-react-remote-br",
        active: true,
        target_stacks: [ "react" ],
        target_titles: [ "frontend", "developer", "engineer" ],
        seniority_terms: [ "senior", "sênior", "sr" ],
        location_terms: [ "remote", "remoto", "brasil", "brazil" ],
        negative_terms: SearchProfile::DEFAULT_NEGATIVE_TERMS,
        required_remote: true,
        include_women_only: false,
        language_scope: :both,
        scan_window_days: 14
      )

      assert_difference("JobMatch.for_profile(profile).count", 1) do
        count = Bootstrapper.new(search_profile: profile).call
        assert_equal 1, count
      end

      match = JobMatch.for_profile(profile).find_by!(job:)
      assert_equal "strong", match.match_strength
      assert_equal "new_match", match.user_state
    end
  end
end
