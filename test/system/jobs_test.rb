require "application_system_test_case"

class JobsTest < ApplicationSystemTestCase
  test "mobile radar renders jobs as cards instead of a wide table" do
    visit new_session_path
    sign_in_as(users(:one))
    page.driver.browser.manage.window.resize_to(390, 844)

    visit jobs_path(search_profile_id: search_profiles(:default).id, user_state: :all)

    assert_text "Radar de vagas"
    assert_selector "[data-testid='filtered-results-summary']", text: "2 vagas retornadas"
    assert_selector "[data-testid='mobile-job-list']", visible: true
    assert_no_selector "[data-testid='desktop-job-table']", visible: true

    summary_top = page.evaluate_script("document.querySelector('[data-testid=\"filtered-results-summary\"]').getBoundingClientRect().top")
    list_top = page.evaluate_script("document.querySelector('[data-testid=\"mobile-job-list\"]').getBoundingClientRect().top")
    assert_operator summary_top, :<, list_top

    within "[data-testid='mobile-job-list']" do
      assert_link "Frontend Engineer Senior"
      assert_text "Memed"
      assert_text "Trabalho remoto"
      assert_text "Gupy"
      assert_link "Detalhes"
      assert_button "Abrir"
      assert_button "Vista"
      assert_button "Aplicada"
      assert_button "Ignorar"
    end
  end

  test "mobile job details show captured description and match context" do
    visit new_session_path
    sign_in_as(users(:one))
    page.driver.browser.manage.window.resize_to(390, 844)

    visit job_path(jobs(:react_role), search_profile_id: search_profiles(:default).id)

    assert_text "Frontend Engineer Senior"
    assert_text "Leia a vaga sem sair do radar"
    assert_text(/por que deu match/i)
    assert_text "Desenvolver interfaces React"
    assert_text "Experiencia com React"
    assert_text "Trabalho remoto no Brasil"
    assert_text(/link original/i)
    assert_button "Abrir candidatura"
  end

  private
    def sign_in_as(user)
      session = user.sessions.create!(user_agent: "System Test", ip_address: "127.0.0.1")
      signed_session_id = ActionDispatch::TestRequest.create.cookie_jar.tap { |cookie_jar| cookie_jar.signed[:session_id] = session.id }[:session_id]

      page.driver.browser.manage.add_cookie(name: "session_id", value: signed_session_id, path: "/")
    end
end
