require "application_system_test_case"

class SearchProfilesTest < ApplicationSystemTestCase
  class FakeIntentCompiler
    def call(technology_intent:, seniority_preset:, language_scope:, required_remote:, region_scope:, include_women_only:)
      raise ArgumentError, "expected servicenow stack" unless technology_intent == "ServiceNow"
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
      fill_in "Tecnologia / stack", with: "ServiceNow"
      click_button "Gerar variacoes"

      assert_text(/preview gerado/i)
      assert_text "servicenow developer"
      assert_selector "input[name='search_profile[compiled_profile_payload]']", visible: false

      click_button "Salvar manualmente"

      assert_current_path jobs_path, ignore_query: true
      assert_text "Radar de vagas"

      profile = SearchProfile.order(:created_at).last
      assert_equal "Senior ServiceNow Remote BR/LatAm", profile.name
      assert_equal [ "servicenow" ], profile.target_stacks
      assert profile.intent_backed?
      assert_includes profile.compiler_stack_aliases["servicenow"], "itsm"
      end
    end
  end

  test "first access onboarding creates a profile from three fields" do
    visit new_session_path
    sign_in_as(users(:three))

    visit root_path

    assert_text "Monte seu primeiro radar"
    fill_in "Linguagens / stack", with: "Salesforce, React"
    select "Senior", from: "Senioridade"
    select "Português", from: "Idioma alvo"
    click_button "Criar perfil e iniciar busca"

    assert_current_path jobs_path, ignore_query: true
    assert_text "Radar de vagas"

    profile = SearchProfile.order(:created_at).last
    assert_equal [ "salesforce", "react" ], profile.target_stacks
    assert_equal "portuguese", profile.language_scope
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
      original_setup_hint = SearchProfiles::CompilerClient.method(:setup_hint)

      SearchProfiles::CompilerClient.singleton_class.send(:define_method, :available?) { true }
      SearchProfiles::CompilerClient.singleton_class.send(:define_method, :setup_hint) { "Compiler disponível no teste" }
      yield
    ensure
      SearchProfiles::CompilerClient.singleton_class.send(:define_method, :available?) { |*args, **kwargs| original_available.call(*args, **kwargs) }
      SearchProfiles::CompilerClient.singleton_class.send(:define_method, :setup_hint) { |*args, **kwargs| original_setup_hint.call(*args, **kwargs) }
    end
end
