require "test_helper"

class JobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "should get index" do
    get jobs_path
    assert_response :success
    assert_match("Radar de vagas", response.body)
    assert_no_match("Codex + Rails", response.body)
    assert_match("Idioma", response.body)
    assert_match("1 vaga retornada", response.body)
    assert_match("Frontend Engineer Senior", response.body)
    assert_match('rel="noopener"', response.body)
    assert_no_match('rel="noreferrer"', response.body)
    assert_no_match("Senior Ruby on Rails Developer", response.body)
  end

  test "should allow switching to all jobs tab" do
    get jobs_path(user_state: :all)

    assert_response :success
    assert_match("2 vagas retornadas", response.body)
    assert_match("Frontend Engineer Senior", response.body)
    assert_match("Senior Ruby on Rails Developer", response.body)
  end

  test "should get show" do
    get job_path(jobs(:react_role))
    assert_response :success
    assert_match("Frontend Engineer Senior", response.body)
    assert_match("Descricao capturada", response.body)
    assert_match("Leia a vaga sem sair do radar", response.body)
    assert_match("Por que deu match", response.body)
    assert_match("Desenvolver interfaces React", response.body)
    assert_match("Experiencia com React", response.body)
    assert_match("Trabalho remoto no Brasil", response.body)
    assert_match("Link original", response.body)
    assert_match(ERB::Util.html_escape(jobs(:react_role).canonical_url), response.body)
  end

  test "marks job as applied" do
    patch mark_job_path(jobs(:react_role), search_profile_id: search_profiles(:default).id, user_state: :applied)

    assert_redirected_to job_path(jobs(:react_role), search_profile_id: search_profiles(:default).id)
    assert_equal("applied", job_matches(:react_default).reload.user_state)

    follow_redirect!
    assert_match("Vaga marcada como aplicada.", response.body)
  end

  test "opening a job marks a new match as seen for the selected profile" do
    post open_job_path(jobs(:react_role), search_profile_id: search_profiles(:default).id)

    assert_response :success
    assert_match "Abrindo candidatura", response.body
    assert_match ERB::Util.html_escape(jobs(:react_role).apply_url), response.body
    assert_equal("seen", job_matches(:react_default).reload.user_state)
  end

  test "opening a job does not downgrade an applied match" do
    job_matches(:react_default).update!(user_state: :applied)

    post open_job_path(jobs(:react_role), search_profile_id: search_profiles(:default).id)

    assert_response :success
    assert_match "Abrindo candidatura", response.body
    assert_equal("applied", job_matches(:react_default).reload.user_state)
  end

  test "redirects users without profiles to onboarding instead of creating a default profile" do
    sign_out
    sign_in_as(users(:three))

    assert_no_difference("SearchProfile.count") do
      get jobs_path
    end

    assert_redirected_to new_search_profile_path(onboarding: 1)
  end

  test "filters by national market and keeps the market across pagination" do
    profile = create_market_profile

    get jobs_path(search_profile_id: profile.id, market: "national")

    assert_response :success
    assert_match "26 vagas retornadas", response.body
    assert_select "a[aria-current=page]", text: "Nacionais", count: 1
    assert_select "a[aria-current=page]", text: "Todas", count: 0
    assert_no_match "sem mercado identificado", response.body

    get jobs_path(search_profile_id: profile.id, market: "national", page: 2)

    assert_response :success
    assert_match "Pagina 2 de 2", response.body
    assert_match "26-26", response.body
    assert_select "a[href=?]", jobs_path(search_profile_id: profile.id, market: "national", page: 1)
    assert_select "input[type=hidden][name=market][value=national]", count: 1
  end

  test "filters by international market" do
    profile = create_market_profile

    get jobs_path(search_profile_id: profile.id, market: "international")

    assert_response :success
    assert_match "1 vaga retornada", response.body
    assert_select "a[aria-current=page]", text: "Internacionais", count: 1
  end

  test "default tab shows every market and the unknown notice" do
    profile = create_market_profile

    get jobs_path(search_profile_id: profile.id)

    assert_response :success
    assert_match "30 vagas retornadas", response.body
    assert_select "a[aria-current=page]", text: "Todas", count: 1
    assert_match "3 sem mercado identificado", response.body
    assert_select "input[type=hidden][name=market]", count: 0
  end

  test "ignores unknown and invalid market params instead of filtering" do
    profile = create_market_profile

    %w[all unknown bogus].each do |market|
      get jobs_path(search_profile_id: profile.id, market:)

      assert_response :success
      assert_match "30 vagas retornadas", response.body
      assert_select "a[aria-current=page]", text: "Todas", count: 1
      assert_select "input[type=hidden][name=market]", count: 0
    end
  end

  test "switching market pills resets the page and keeps other filters" do
    profile = create_market_profile

    get jobs_path(search_profile_id: profile.id, market: "national", page: 2, q: "Frontend")

    assert_response :success
    assert_select "a[href=?]", jobs_path(search_profile_id: profile.id, q: "Frontend", market: "international")
    assert_select "a[href=?]", jobs_path(search_profile_id: profile.id, q: "Frontend")
    assert_select "input[type=hidden][name=market][value=national]", count: 1
    assert_select "input[name=q][value=?]", "Frontend", count: 1
  end

  test "status tabs keep the normalized market and drop the page" do
    profile = create_market_profile

    get jobs_path(search_profile_id: profile.id, market: "national", page: 2, q: "Frontend")

    assert_response :success
    assert_select "a[href=?]", jobs_path(search_profile_id: profile.id, market: "national", q: "Frontend", user_state: "applied")
  end

  test "bogus market is not echoed into links or the hidden form field" do
    profile = create_market_profile

    get jobs_path(search_profile_id: profile.id, market: "bogus", page: 2)

    assert_response :success
    assert_select "input[name=market]", count: 0
    assert_select "a[href*=bogus]", count: 0
  end

  test "unknown notice counts unknown matches of the selected profile under the current filters" do
    profile = create_market_profile
    other_profile = SearchProfile.create!(SearchProfile.default_attributes.merge(user: users(:one), name: "Outro", slug: "outro"))
    other_user_profile = SearchProfile.create!(SearchProfile.default_attributes.merge(user: users(:two), name: "Outro usuario", slug: "outro-usuario"))
    create_market_match(profile: other_profile, slug: "other-profile-unknown", title: "Frontend Engineer Other", location_text: "Remote")
    create_market_match(profile: other_user_profile, slug: "other-user-unknown", title: "Frontend Engineer Other User", location_text: "Remote")

    get jobs_path(search_profile_id: profile.id)
    assert_match "3 sem mercado identificado", response.body

    get jobs_path(search_profile_id: profile.id, q: "Frontend")
    assert_match "2 sem mercado identificado", response.body

    get jobs_path(search_profile_id: profile.id, market: "national")
    assert_no_match "sem mercado identificado", response.body
  end

  private
    def create_market_profile
      profile = SearchProfile.create!(SearchProfile.default_attributes.merge(user: users(:one), name: "Mercado", slug: "mercado"))

      26.times do |index|
        create_market_match(profile:, slug: "national-#{index}", title: "Ruby Engineer #{index}", location_text: "Brasil")
      end
      create_market_match(profile:, slug: "international", title: "Frontend Engineer Global", location_text: "Worldwide")
      create_market_match(profile:, slug: "unknown-a", title: "Frontend Engineer Remote A", location_text: "Remote")
      create_market_match(profile:, slug: "unknown-b", title: "Frontend Engineer Remote B", location_text: "Remote")
      create_market_match(profile:, slug: "unknown-c", title: "Backend Engineer Remote C", location_text: "Remote")
      create_market_match(profile:, slug: "unknown-seen", title: "Frontend Engineer Remote D", location_text: "Remote", user_state: :seen)

      profile
    end

    def create_market_match(profile:, slug:, title:, location_text:, user_state: :new_match)
      job = Job.create!(
        job_source: job_sources(:gupy),
        title:,
        company_name: "Acme #{slug}",
        apply_url: "https://acme.example/jobs/#{slug}",
        canonical_url: "https://acme.example/jobs/#{slug}",
        source_url: "https://acme.example/jobs/#{slug}",
        remote_text: "",
        location_text:,
        lifecycle_state: :active,
        posted_text: "publicada hoje",
        published_at: Time.current,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        last_validated_at: Time.current,
        fingerprint: "#{slug}::market"
      )
      JobMatch.create!(
        search_profile: profile,
        job:,
        match_strength: :strong,
        user_state:,
        score: 90,
        reason: "Mercado #{slug}",
        seniority: "senior",
        stack_tags: [ "react" ],
        eligibility_flags: [],
        raw_decision: {},
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        last_validated_at: Time.current
      )
    end
end
