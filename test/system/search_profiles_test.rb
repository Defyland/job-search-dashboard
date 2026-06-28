require "application_system_test_case"

class SearchProfilesTest < ApplicationSystemTestCase
  class FakeIntentCompiler
    def call(technology_intent:, seniority_preset:, language_scope:, required_remote:, region_scope:, include_women_only:)
      raise ArgumentError, "expected servicenow stack" unless technology_intent == "servicenow"
      raise ArgumentError, "unexpected seniority" unless seniority_preset == "senior"
      raise ArgumentError, "unexpected language" unless language_scope == "both"
      raise ArgumentError, "unexpected remote flag" unless required_remote == "1" || required_remote == true
      raise ArgumentError, "unexpected region" unless region_scope == "brazil_latam"
      raise ArgumentError, "unexpected women flag" unless include_women_only == "0" || include_women_only == false

      {
        "profile_name_suggestion" => "Senior ServiceNow Remote BR/LatAm",
        "canonical_stacks" => [ "servicenow" ],
        "title_variants_pt" => [ "desenvolvedor servicenow", "engenheiro servicenow" ],
        "title_variants_en" => [ "servicenow developer", "servicenow engineer" ],
        "stack_aliases" => [
          { "canonical_stack" => "servicenow", "aliases" => [ "itsm", "flow designer", "integration hub" ] }
        ],
        "model" => "claude-sonnet-4-20250514",
        "provider" => "anthropic"
      }
    end
  end

  test "creates an intent-backed profile through the real browser flow" do
    with_compiler_available do
      with_fake_intent_compiler(FakeIntentCompiler.new) do
      visit new_session_path
      sign_in_as(users(:one))

      visit new_search_profile_path
      fill_in "Linguagem / stack", with: "ServiceNow"
      select "45 dias", from: "Buscar vagas desde"
      click_button "Gerar variacoes"

      assert_text(/preview gerado/i)
      assert_text "servicenow developer"
      assert_selector "input[name='search_profile[compiled_profile_payload]']", visible: false

      click_button "Criar perfil e iniciar busca"

      assert_current_path jobs_path, ignore_query: true
      assert_text "Radar de vagas"
      assert_text(/perfil ativo/i)
      assert_text "Senior ServiceNow Remote BR/LatAm"
      assert_text "Janela 45 dias"
      assert_text "Busca enfileirada"

      profile = SearchProfile.order(:created_at).last
      assert_equal "Senior ServiceNow Remote BR/LatAm", profile.name
      assert_equal [ "servicenow" ], profile.target_stacks
      assert_equal 45, profile.scan_window_days
      assert profile.intent_backed?
      assert_includes profile.compiler_stack_aliases["servicenow"], "itsm"
      end
    end
  end

  test "first access onboarding creates a profile from stack and scan window" do
    visit new_session_path
    sign_in_as(users(:three))

    visit root_path

    assert_text "Crie o radar pela stack"
    fill_in "Linguagem / stack", with: "Salesforce, React"
    select "30 dias", from: "Buscar vagas desde"
    click_button "Gerar variacoes"

    assert_text(/preview gerado/i)
    assert_text "salesforce developer"

    click_button "Criar perfil e iniciar busca"

    assert_current_path jobs_path, ignore_query: true
    assert_text "Radar de vagas"

    profile = SearchProfile.order(:created_at).last
    assert_equal [ "react", "salesforce" ], profile.target_stacks.sort
    assert_equal "both", profile.language_scope
    assert_equal 30, profile.scan_window_days
  end

  test "mobile profile creation stays on the simple stack flow" do
    visit new_session_path
    sign_in_as(users(:three))
    page.driver.browser.manage.window.resize_to(390, 844)

    visit new_search_profile_path(onboarding: 1)

    assert_text "Crie o radar pela stack"
    assert_field "Linguagem / stack"
    assert_field "Nivel"
    assert_no_text "Modo avancado"

    fill_in "Linguagem / stack", with: "Java"
    select "Pleno", from: "Nivel"
    select "14 dias", from: "Buscar vagas desde"
    click_button "Gerar variacoes"

    assert_text(/preview gerado/i)
    assert_text "Pleno Java Remote Brasil e LatAm"
    assert_text "java developer"
    assert_button "Criar perfil e iniciar busca"
  end

  private
    def sign_in_as(user)
      session = user.sessions.create!(user_agent: "System Test", ip_address: "127.0.0.1")
      signed_session_id = ActionDispatch::TestRequest.create.cookie_jar.tap { |cookie_jar| cookie_jar.signed[:session_id] = session.id }[:session_id]

      page.driver.browser.manage.add_cookie(name: "session_id", value: signed_session_id, path: "/")
    end

    def with_fake_intent_compiler(fake_compiler)
      original_new = SearchProfiles::IntentCompiler.method(:new)
      SearchProfiles::IntentCompiler.singleton_class.send(:define_method, :new) { |_args = nil, **_kwargs| fake_compiler }
      yield
    ensure
      SearchProfiles::IntentCompiler.singleton_class.send(:define_method, :new) do |*args, **kwargs|
        original_new.call(*args, **kwargs)
      end
    end

    def with_compiler_available
      original_available = SearchProfiles::CompilerClient.method(:available?)

      SearchProfiles::CompilerClient.singleton_class.send(:define_method, :available?) { true }
      yield
    ensure
      SearchProfiles::CompilerClient.singleton_class.send(:define_method, :available?) { |*args, **kwargs| original_available.call(*args, **kwargs) }
    end
end
