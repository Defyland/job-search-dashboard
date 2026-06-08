require "test_helper"

class JobMatchFiltersTest < ActiveSupport::TestCase
  test "filters matches by profile scoped stack and user state" do
    filtered = JobMatchFilters.new(
      scope: JobMatch.for_profile(search_profiles(:default)).includes(job: :job_source),
      params: { stack: "react", user_state: "new_match", lifecycle_state: "active" }
    ).call

    assert_equal [ job_matches(:react_default) ], filtered.to_a
  end

  test "filters matches by title language" do
    portuguese_job = Job.create!(
      job_source: job_sources(:gupy),
      title: "Desenvolvedor Frontend Sênior React",
      company_name: "Acme BR",
      apply_url: "https://acme.example/jobs/react-pt",
      canonical_url: "https://acme.example/jobs/react-pt",
      source_url: "https://acme.example/jobs/react-pt",
      remote_text: "Remoto Brasil",
      location_text: "Brasil",
      lifecycle_state: :active,
      posted_text: "publicada hoje",
      published_at: Time.current,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      last_validated_at: Time.current,
      fingerprint: "acme-br::react-pt"
    )
    portuguese_match = JobMatch.create!(
      search_profile: search_profiles(:default),
      job: portuguese_job,
      match_strength: :strong,
      user_state: :new_match,
      score: 95,
      reason: "Titulo em português com React.",
      seniority: "senior",
      stack_tags: [ "react" ],
      eligibility_flags: [],
      raw_decision: {},
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      last_validated_at: Time.current
    )

    english_filtered = JobMatchFilters.new(
      scope: JobMatch.for_profile(search_profiles(:default)).includes(job: :job_source),
      params: { title_language: "english", lifecycle_state: "active" }
    ).call
    portuguese_filtered = JobMatchFilters.new(
      scope: JobMatch.for_profile(search_profiles(:default)).includes(job: :job_source),
      params: { title_language: "portuguese", lifecycle_state: "active" }
    ).call

    assert_includes english_filtered, job_matches(:react_default)
    assert_not_includes english_filtered, portuguese_match
    assert_includes portuguese_filtered, portuguese_match
    assert_not_includes portuguese_filtered, job_matches(:react_default)
  end
end
