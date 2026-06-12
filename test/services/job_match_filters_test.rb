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

  test "filters matches by job contract type" do
    jobs(:react_role).update!(raw_payload: { employmentType: "contractor" })
    jobs(:ruby_role).update!(raw_payload: { regime: "CLT" })

    pj_filtered = JobMatchFilters.new(
      scope: JobMatch.for_profile(search_profiles(:default)).includes(job: :job_source),
      params: { contract_type: "pj", lifecycle_state: "active" }
    ).call
    clt_filtered = JobMatchFilters.new(
      scope: JobMatch.for_profile(search_profiles(:default)).includes(job: :job_source),
      params: { contract_type: "clt", lifecycle_state: "active" }
    ).call

    assert_includes pj_filtered, job_matches(:react_default)
    assert_not_includes pj_filtered, job_matches(:ruby_default)
    assert_includes clt_filtered, job_matches(:ruby_default)
    assert_not_includes clt_filtered, job_matches(:react_default)
  end

  test "sorts newest by when the match entered the radar" do
    older_posted_job = Job.create!(
      job_source: job_sources(:gupy),
      title: "Senior React Engineer",
      company_name: "Late Arrival",
      apply_url: "https://acme.example/jobs/late-arrival",
      canonical_url: "https://acme.example/jobs/late-arrival",
      source_url: "https://acme.example/jobs/late-arrival",
      remote_text: "Remoto",
      location_text: "Brasil",
      lifecycle_state: :active,
      posted_text: "publicada ha 30 dias",
      published_at: 30.days.ago,
      first_seen_at: 1.hour.ago,
      last_seen_at: 1.hour.ago,
      last_validated_at: 1.hour.ago,
      fingerprint: "late-arrival::senior-react-engineer"
    )
    newer_posted_job = Job.create!(
      job_source: job_sources(:gupy),
      title: "Senior React Native Engineer",
      company_name: "Old Inbox",
      apply_url: "https://acme.example/jobs/old-inbox",
      canonical_url: "https://acme.example/jobs/old-inbox",
      source_url: "https://acme.example/jobs/old-inbox",
      remote_text: "Remoto",
      location_text: "Brasil",
      lifecycle_state: :active,
      posted_text: "publicada ha 2 dias",
      published_at: 2.days.ago,
      first_seen_at: 10.days.ago,
      last_seen_at: 1.day.ago,
      last_validated_at: 1.day.ago,
      fingerprint: "old-inbox::senior-react-native-engineer"
    )

    late_arrival_match = JobMatch.create!(
      search_profile: search_profiles(:default),
      job: older_posted_job,
      match_strength: :strong,
      user_state: :new_match,
      score: 90,
      reason: "Entrou no radar agora.",
      seniority: "senior",
      stack_tags: [ "react" ],
      eligibility_flags: [],
      raw_decision: {},
      first_seen_at: 1.hour.ago,
      last_seen_at: 1.hour.ago,
      last_validated_at: 1.hour.ago
    )
    old_inbox_match = JobMatch.create!(
      search_profile: search_profiles(:default),
      job: newer_posted_job,
      match_strength: :strong,
      user_state: :new_match,
      score: 91,
      reason: "Ja estava no radar faz tempo.",
      seniority: "senior",
      stack_tags: [ "react native" ],
      eligibility_flags: [],
      raw_decision: {},
      first_seen_at: 10.days.ago,
      last_seen_at: 1.day.ago,
      last_validated_at: 1.day.ago
    )

    filtered = JobMatchFilters.new(
      scope: JobMatch.for_profile(search_profiles(:default)).includes(job: :job_source),
      params: { lifecycle_state: "active", user_state: "new_match", sort: "newest" }
    ).call.limit(3).to_a

    assert_equal late_arrival_match, filtered.first
    assert_includes filtered, old_inbox_match
  end
end
