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
    older_posted_job = create_job(
      title: "Senior React Engineer",
      company_name: "Late Arrival",
      slug: "late-arrival",
      posted_text: "publicada ha 30 dias",
      published_at: 30.days.ago,
      seen_at: 1.hour.ago
    )
    newer_posted_job = create_job(
      title: "Senior React Native Engineer",
      company_name: "Old Inbox",
      slug: "old-inbox",
      posted_text: "publicada ha 2 dias",
      published_at: 2.days.ago,
      seen_at: 10.days.ago,
      last_seen_at: 1.day.ago
    )

    late_arrival_match = create_match(
      search_profile: search_profiles(:default),
      job: older_posted_job,
      score: 90,
      reason: "Entrou no radar agora.",
      stack_tags: [ "react" ],
      seen_at: 1.hour.ago
    )
    old_inbox_match = create_match(
      search_profile: search_profiles(:default),
      job: newer_posted_job,
      score: 91,
      reason: "Ja estava no radar faz tempo.",
      stack_tags: [ "react native" ],
      seen_at: 10.days.ago,
      last_seen_at: 1.day.ago
    )

    filtered = JobMatchFilters.new(
      scope: JobMatch.for_profile(search_profiles(:default)).includes(job: :job_source),
      params: { lifecycle_state: "active", user_state: "new_match", sort: "newest" }
    ).call.limit(3).to_a

    assert_equal late_arrival_match, filtered.first
    assert_includes filtered, old_inbox_match
  end

  test "sorts same capture timestamp with stable id tie breaker" do
    profile = SearchProfile.create!(
      SearchProfile.default_attributes.merge(user: users(:one), name: "Ordering tie breaker", slug: "ordering-tie-breaker")
    )
    source = job_sources(:gupy)
    captured_at = 2.hours.ago

    first_job = create_job(
      title: "Senior React Engineer A",
      company_name: "Batch A",
      source:,
      slug: "batch-a",
      seen_at: captured_at
    )
    second_job = create_job(
      title: "Senior React Engineer B",
      company_name: "Batch B",
      source:,
      slug: "batch-b",
      seen_at: captured_at
    )

    first_match = create_match(
      search_profile: profile,
      job: first_job,
      score: 90,
      reason: "Entrou no mesmo lote.",
      stack_tags: [ "react" ],
      seen_at: captured_at
    )
    second_match = create_match(
      search_profile: profile,
      job: second_job,
      score: 91,
      reason: "Entrou no mesmo lote depois.",
      stack_tags: [ "react" ],
      seen_at: captured_at
    )
    first_match.update_columns(updated_at: 1.hour.from_now)

    filtered = JobMatchFilters.new(
      scope: JobMatch.for_profile(profile).includes(job: :job_source),
      params: { lifecycle_state: "active", user_state: "new_match", sort: "newest" }
    ).call.to_a

    assert_equal [ second_match, first_match ], filtered
  end

  private
    def create_job(title:, company_name:, slug:, source: job_sources(:gupy), posted_text: "publicada hoje", published_at: 1.day.ago, seen_at: Time.current, last_seen_at: seen_at)
      Job.create!(
        job_source: source,
        title:,
        company_name:,
        apply_url: "https://acme.example/jobs/#{slug}",
        canonical_url: "https://acme.example/jobs/#{slug}",
        source_url: "https://acme.example/jobs/#{slug}",
        remote_text: "Remoto",
        location_text: "Brasil",
        lifecycle_state: :active,
        posted_text:,
        published_at:,
        first_seen_at: seen_at,
        last_seen_at:,
        last_validated_at: last_seen_at,
        fingerprint: "#{slug}::#{title.parameterize}"
      )
    end

    def create_match(search_profile:, job:, score:, reason:, stack_tags:, seen_at:, last_seen_at: seen_at)
      JobMatch.create!(
        search_profile:,
        job:,
        match_strength: :strong,
        user_state: :new_match,
        score:,
        reason:,
        seniority: "senior",
        stack_tags:,
        eligibility_flags: [],
        raw_decision: {},
        first_seen_at: seen_at,
        last_seen_at:,
        last_validated_at: last_seen_at
      )
    end
end
