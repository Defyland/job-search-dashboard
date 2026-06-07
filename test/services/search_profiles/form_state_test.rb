require "test_helper"

module SearchProfiles
  class FormStateTest < ActiveSupport::TestCase
    test "hydrates the simple form state without losing persisted defaults" do
      profile = search_profiles(:default)

      state = FormState.new(
        search_profile: profile,
        submitted_attributes: {
          "technology_intent" => "java",
          "region_scope" => "brazil",
          "required_remote" => "0",
          "active" => "0",
          "compiled_profile_payload" => "signed-token"
        },
        compiled_preview: { "canonical_stacks" => [ "java" ] }
      )

      assert_equal "java", state.simple_input["technology_intent"]
      assert_equal "Senior Ruby/Rails/React Remote BR/LatAm", state.hydrated_simple_input["name"]
      assert_equal "signed-token", state.compiled_profile_payload
      assert_equal "0", state.active_default
      assert state.advanced_open?
    end
  end
end
