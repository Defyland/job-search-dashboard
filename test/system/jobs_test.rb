require "application_system_test_case"

class JobsTest < ApplicationSystemTestCase
  test "mobile radar renders jobs as cards instead of a wide table" do
    visit new_session_path
    sign_in_as(users(:one))
    page.driver.browser.manage.window.resize_to(390, 844)

    visit jobs_path(search_profile_id: search_profiles(:default).id, user_state: :all)

    assert_text "Radar de vagas"
    assert_selector "[data-testid='mobile-job-list']", visible: true
    assert_no_selector "[data-testid='desktop-job-table']", visible: true

    within "[data-testid='mobile-job-list']" do
      assert_link "Frontend Engineer Senior"
      assert_text "Memed"
      assert_text "Trabalho remoto"
      assert_text "Gupy"
      assert_button "Abrir"
      assert_button "Vista"
      assert_button "Aplicada"
      assert_button "Ignorar"
    end
  end

  private
    def sign_in_as(user)
      session = user.sessions.create!(user_agent: "System Test", ip_address: "127.0.0.1")
      signed_session_id = ActionDispatch::TestRequest.create.cookie_jar.tap { |cookie_jar| cookie_jar.signed[:session_id] = session.id }[:session_id]

      page.driver.browser.manage.add_cookie(name: "session_id", value: signed_session_id, path: "/")
    end
end
