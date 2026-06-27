require "application_system_test_case"

class NavigationTest < ApplicationSystemTestCase
  test "mobile header menu exposes the primary navigation" do
    visit new_session_path
    sign_in_as(users(:one))
    page.driver.browser.manage.window.resize_to(390, 844)

    visit jobs_path(search_profile_id: search_profiles(:default).id)

    assert_text "Radar de vagas"
    assert_selector "summary", text: "Menu"

    find("summary", text: "Menu").click

    within "details[open]" do
      assert_link "Vagas", href: jobs_path
      assert_link "Perfis", href: search_profiles_path
      assert_link "Runs", href: search_runs_path
      assert_link "Fontes", href: sources_path
      click_link "Perfis"
    end

    assert_current_path search_profiles_path
    assert_text "Perfis de busca"
  end

  private
    def sign_in_as(user)
      session = user.sessions.create!(user_agent: "System Test", ip_address: "127.0.0.1")
      signed_session_id = ActionDispatch::TestRequest.create.cookie_jar.tap { |cookie_jar| cookie_jar.signed[:session_id] = session.id }[:session_id]

      page.driver.browser.manage.add_cookie(name: "session_id", value: signed_session_id, path: "/")
    end
end
