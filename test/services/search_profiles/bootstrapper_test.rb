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
        lifecycle_state: :active,
        posted_text: "publicada ha 1 dia",
        published_at: 1.day.ago,
        first_seen_at: 1.day.ago,
        last_seen_at: 1.day.ago,
        last_validated_at: 1.day.ago,
        fingerprint: "nova::senior react engineer::gupy.io::react-1",
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
        count = Bootstrapper.new(search_profile: profile, job_scope: Job.where(id: job.id).includes(:job_source)).call
        assert_equal 1, count
      end

      match = JobMatch.for_profile(profile).find_by!(job:)
      assert_equal "strong", match.match_strength
      assert_equal "new_match", match.user_state
    end

    test "prunes stale matches when profile terms change" do
      ruby_job = Job.create!(
        job_source: job_sources(:workable),
        title: "Senior Ruby Engineer",
        company_name: "Legacy",
        apply_url: "https://jobs.workable.com/view/ruby-1",
        canonical_url: "https://jobs.workable.com/view/ruby-1",
        source_url: "https://jobs.workable.com/view/ruby-1",
        ats_name: "Workable",
        external_job_id: "ruby-1",
        remote_text: "Remote Brazil",
        location_text: "Brasil",
        lifecycle_state: :active,
        posted_text: "publicada ha 2 dias",
        published_at: 2.days.ago,
        first_seen_at: 2.days.ago,
        last_seen_at: 1.day.ago,
        last_validated_at: 1.day.ago,
        fingerprint: "legacy::senior ruby engineer::jobs.workable.com::ruby-1",
        raw_payload: {
          title: "Senior Ruby Engineer",
          company: "Legacy",
          description: "Ruby, Rails, remote Brazil"
        }
      )
      react_job = Job.create!(
        job_source: job_sources(:gupy),
        title: "Senior React Engineer",
        company_name: "Nova",
        apply_url: "https://nova.gupy.io/jobs/react-2",
        canonical_url: "https://nova.gupy.io/jobs/react-2",
        source_url: "https://nova.gupy.io/jobs/react-2",
        ats_name: "Gupy",
        external_job_id: "react-2",
        remote_text: "Remoto Brasil",
        location_text: "Brasil",
        lifecycle_state: :active,
        posted_text: "publicada ha 1 dia",
        published_at: 1.day.ago,
        first_seen_at: 1.day.ago,
        last_seen_at: 1.day.ago,
        last_validated_at: 1.day.ago,
        fingerprint: "nova::senior react engineer::gupy.io::react-2",
        raw_payload: {
          title: "Senior React Engineer",
          company: "Nova",
          description: "React, TypeScript, remote Brazil"
        }
      )

      profile = users(:one).search_profiles.create!(
        name: "Senior Ruby Remote BR",
        slug: "senior-ruby-remote-br",
        active: true,
        target_stacks: [ "ruby" ],
        target_titles: [ "developer", "engineer" ],
        seniority_terms: [ "senior", "sênior", "sr" ],
        location_terms: [ "remote", "remoto", "brasil", "brazil" ],
        negative_terms: SearchProfile::DEFAULT_NEGATIVE_TERMS,
        required_remote: true,
        include_women_only: false,
        language_scope: :both,
        scan_window_days: 14
      )

      Bootstrapper.new(search_profile: profile, job_scope: Job.where(id: [ ruby_job.id, react_job.id ]).includes(:job_source)).call
      assert_equal [ ruby_job.id ], JobMatch.for_profile(profile).pluck(:job_id)

      profile.update!(target_stacks: [ "react" ])

      Bootstrapper.new(
        search_profile: profile,
        job_scope: Job.where(id: [ ruby_job.id, react_job.id ]).includes(:job_source),
        prune_stale: true
      ).call

      assert_equal [ react_job.id ], JobMatch.for_profile(profile).pluck(:job_id)
    end
  end
end
