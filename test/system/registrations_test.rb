require "application_system_test_case"

class RegistrationsTest < ApplicationSystemTestCase
  test "visitor creates account and reaches profile onboarding" do
    visit root_path
    click_link "Criar conta", match: :first

    assert_current_path new_registration_path
    fill_in "Email", with: "browser-signup@example.com"
    fill_in "Senha", with: "password123"
    fill_in "Confirmar senha", with: "password123"
    click_button "Criar conta"

    assert_current_path new_search_profile_path, ignore_query: true
    assert_text "Crie o radar pela stack"
    assert User.exists?(email_address: "browser-signup@example.com")
  end
end
