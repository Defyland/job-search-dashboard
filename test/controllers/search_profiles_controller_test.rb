require "cgi"
require "test_helper"

class SearchProfilesControllerTest < ActionDispatch::IntegrationTest
  class FakeIntentCompiler
    def call(technology_intent:, seniority_preset:, language_scope:, required_remote:, region_scope:, include_women_only:)
      raise ArgumentError, "expected salesforce stack" unless technology_intent == "salesforce"
      raise ArgumentError, "unexpected seniority" unless seniority_preset == "senior"
      raise ArgumentError, "unexpected language" unless language_scope == "both"
      raise ArgumentError, "unexpected remote flag" unless required_remote == "1" || required_remote == true
      raise ArgumentError, "unexpected region" unless region_scope == "brazil_latam"
      raise ArgumentError, "unexpected women flag" unless include_women_only == "0" || include_women_only == false

      {
        "profile_name_suggestion" => "Senior Salesforce Remote BR/LatAm",
        "canonical_stacks" => [ "salesforce" ],
        "title_variants_pt" => [ "desenvolvedor salesforce", "consultor salesforce" ],
        "title_variants_en" => [ "salesforce developer", "salesforce engineer" ],
        "stack_aliases" => [
          { "canonical_stack" => "salesforce", "aliases" => [ "apex", "lightning", "sales cloud" ] }
        ],
        "model" => "claude-sonnet-4-20250514",
        "provider" => "anthropic"
      }
    end
  end

  setup do
    sign_in_as(users(:one))
  end

  test "lists search profiles" do
    get search_profiles_path

    assert_response :success
    assert_match "Senior Ruby/Rails/React", response.body
  end

  test "compiles intent preview and saves an intent-backed profile" do
    with_fake_intent_compiler(FakeIntentCompiler.new) do
      post search_profiles_path, params: { search_profile: compiled_form_params, preview_compile: "1" }
    end

    assert_response :success
    assert_match "Preview gerado", response.body
    assert_match "salesforce developer", response.body

    compiled_payload = extract_compiled_payload(response.body)

    assert_difference("SearchProfile.count", 1) do
      post search_profiles_path, params: {
        search_profile: compiled_form_params.merge(
          compiled_profile_payload: compiled_payload
        )
      }
    end

    profile = SearchProfile.order(:created_at).last
    assert_redirected_to jobs_path(search_profile_id: profile.id)
    assert_equal [ "salesforce" ], profile.target_stacks
    assert profile.intent_backed?
    assert_equal "brazil_latam", profile.intent_settings["region_scope"]
    assert_includes profile.compiler_stack_aliases["salesforce"], "apex"
  end

  test "rejects saving with stale compiled payload when the simple intent changes" do
    with_fake_intent_compiler(FakeIntentCompiler.new) do
      post search_profiles_path, params: { search_profile: compiled_form_params, preview_compile: "1" }
    end

    compiled_payload = extract_compiled_payload(response.body)

    assert_no_difference("SearchProfile.count") do
      post search_profiles_path, params: {
        search_profile: compiled_form_params.merge(
          "technology_intent" => "servicenow",
          "compiled_profile_payload" => compiled_payload
        )
      }
    end

    assert_response :unprocessable_entity
    assert_match "Gere novamente antes de salvar", response.body
  end

  test "updates women only preference manually while preserving profile settings" do
    profile = users(:one).search_profiles.create!(
      SearchProfiles::ProfileBuilder.from_compiled(
        simple_input: {
          "name" => "Senior Java Remote",
          "technology_intent" => "java",
          "seniority_preset" => "senior",
          "language_scope" => "both",
          "required_remote" => true,
          "region_scope" => "brazil_latam",
          "include_women_only" => false
        },
        compiled_payload: {
          "profile_name_suggestion" => "Senior Java Remote",
          "canonical_stacks" => [ "java" ],
          "title_variants_pt" => [ "desenvolvedor java" ],
          "title_variants_en" => [ "java developer" ],
          "stack_aliases" => [ { "canonical_stack" => "java", "aliases" => [ "spring boot" ] } ],
          "model" => "claude-sonnet-4-20250514",
          "request_fingerprint" => "fingerprint"
        }
      )
    )

    patch search_profile_path(profile), params: {
      search_profile: {
        name: profile.name,
        required_remote: "1",
        include_women_only: "1",
        language_scope: "both",
        technology_intent: "java",
        seniority_preset: "senior",
        region_scope: "brazil_latam",
        target_stacks_text: profile.target_stacks_text,
        target_titles_text: profile.target_titles_text,
        seniority_terms_text: profile.seniority_terms_text,
        location_terms_text: profile.location_terms_text,
        negative_terms_text: profile.negative_terms_text
      }
    }

    assert_redirected_to search_profiles_path
    assert profile.reload.include_women_only?
    assert profile.intent_backed?
    assert_includes profile.compiler_stack_aliases["java"], "spring boot"
  end

  private
    def compiled_form_params
      {
        name: "Senior Salesforce Remote BR/LatAm",
        technology_intent: "salesforce",
        seniority_preset: "senior",
        language_scope: "both",
        required_remote: "1",
        region_scope: "brazil_latam",
        include_women_only: "0"
      }
    end

    def extract_compiled_payload(body)
      escaped = body[/name="search_profile\[compiled_profile_payload\]".*?value="([^"]+)"/m, 1]
      CGI.unescapeHTML(escaped.to_s)
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
end
