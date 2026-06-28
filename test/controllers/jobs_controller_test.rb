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
    assert_match("Frontend Engineer Senior", response.body)
    assert_match('rel="noopener"', response.body)
    assert_no_match('rel="noreferrer"', response.body)
    assert_no_match("Senior Ruby on Rails Developer", response.body)
  end

  test "should allow switching to all jobs tab" do
    get jobs_path(user_state: :all)

    assert_response :success
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
end
