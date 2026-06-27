require "application_system_test_case"

class NavigationTest < ApplicationSystemTestCase
  test "mobile header menu exposes the primary navigation" do
    visit new_session_path
    sign_in_as(users(:one))
    page.driver.browser.manage.window.resize_to(390, 844)

    visit jobs_path(search_profile_id: search_profiles(:default).id)

    assert_text "Radar de vagas"
    assert_selector "button[aria-controls='primary-mobile-menu'][aria-expanded='false']", text: "Menu"

    find("button", text: "Menu").click

    assert_selector "button[aria-controls='primary-mobile-menu'][aria-expanded='true']", text: "Menu"

    within "#primary-mobile-menu" do
      assert_link "Vagas", href: jobs_path
      assert_link "Perfis", href: search_profiles_path
      assert_link "Runs", href: search_runs_path
      assert_link "Fontes", href: sources_path
    end

    find("h1", text: "Radar de vagas").click
    assert_selector "button[aria-controls='primary-mobile-menu'][aria-expanded='false']", text: "Menu"
    assert_no_selector "#primary-mobile-menu", visible: true

    find("button", text: "Menu").click

    within "#primary-mobile-menu" do
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
