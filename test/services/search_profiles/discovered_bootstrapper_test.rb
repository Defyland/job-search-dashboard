require "test_helper"

module SearchProfiles
  class DiscoveredBootstrapperTest < ActiveSupport::TestCase
    test "reuses recent discovered jobs for a newly matching profile" do
      source = job_sources(:gupy)
      profile = users(:one).search_profiles.create!(
        name: "Senior React Remote BR",
        slug: "senior-react-remote-discovered",
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

      recent_run = SearchRun.create!(
        trigger_source: :manual,
        status: :succeeded,
        window_label: "14d",
        started_at: 2.days.ago,
        finished_at: 2.days.ago,
        summary: {}
      )
      recent_scan = SourceScan.create!(search_run: recent_run, job_source: source, status: :succeeded, finished_at: 2.days.ago)

      old_run = SearchRun.create!(
        trigger_source: :manual,
        status: :succeeded,
        window_label: "14d",
        started_at: 30.days.ago,
        finished_at: 30.days.ago,
        summary: {}
      )
      old_scan = SourceScan.create!(search_run: old_run, job_source: source, status: :succeeded, finished_at: 30.days.ago)

      recent_candidate = DiscoveredJob.create!(
        search_run: recent_run,
        source_scan: recent_scan,
        job_source: source,
        classification: :rejected,
        title: "Senior React Native Engineer",
        company_name: "Nova",
        apply_url: "https://nova.gupy.io/jobs/react-native-1",
        canonical_url: "https://nova.gupy.io/jobs/react-native-1",
        source_url: "https://nova.gupy.io/jobs/react-native-1",
        external_job_id: "react-native-1",
        remote_text: "Remoto Brasil",
        location_text: "Brasil",
        seniority: "senior",
        reason: "nenhum perfil ativo aceitou a vaga",
        posted_text: "publicada ha 2 dias",
        published_at: 2.days.ago,
        stack_tags: [ "react native" ],
        fingerprint: "nova::senior react native engineer::gupy.io::react-native-1",
        payload: {
          "title" => "Senior React Native Engineer",
          "company" => "Nova",
          "description" => "React Native, TypeScript, remote Brazil"
        }
      )

      DiscoveredJob.create!(
        search_run: old_run,
        source_scan: old_scan,
        job_source: source,
        classification: :rejected,
        title: "Senior React Engineer",
        company_name: "Old Nova",
        apply_url: "https://nova.gupy.io/jobs/react-old",
        canonical_url: "https://nova.gupy.io/jobs/react-old",
        source_url: "https://nova.gupy.io/jobs/react-old",
        external_job_id: "react-old",
        remote_text: "Remoto Brasil",
        location_text: "Brasil",
        seniority: "senior",
        reason: "nenhum perfil ativo aceitou a vaga",
        posted_text: "publicada ha 30 dias",
        published_at: 30.days.ago,
        stack_tags: [ "react" ],
        fingerprint: "nova::senior react engineer::gupy.io::react-old",
        payload: {
          "title" => "Senior React Engineer",
          "company" => "Old Nova",
          "description" => "React, remote Brazil"
        }
      )

      assert_difference("Job.count", 1) do
        assert_difference("JobMatch.for_profile(profile).count", 1) do
          assert_difference("SearchRun.count", 1) do
            DiscoveredBootstrapper.new(search_profile: profile).call
          end
        end
      end

      imported_job = Job.find_by!(fingerprint: recent_candidate.fingerprint)
      assert_equal [ imported_job.id ], JobMatch.for_profile(profile).pluck(:job_id)

      cached_run = SearchRun.order(:created_at).last
      assert_equal "manual", cached_run.trigger_source
      assert_equal "discovered_cache", cached_run.summary["discovery_mode"]
      assert_equal profile.id, cached_run.summary["search_profile_id"]
      assert_equal 1, cached_run.imported_count
    end
  end
end
