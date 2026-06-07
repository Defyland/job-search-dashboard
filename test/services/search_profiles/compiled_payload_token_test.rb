require "test_helper"

module SearchProfiles
  class CompiledPayloadTokenTest < ActiveSupport::TestCase
    test "verifies the token against the current simple intent input" do
      simple_input = {
        "name" => "Senior Salesforce Remote",
        "technology_intent" => "salesforce",
        "seniority_preset" => "senior",
        "language_scope" => "both",
        "required_remote" => true,
        "region_scope" => "brazil_latam",
        "include_women_only" => false
      }
      payload = {
        "canonical_stacks" => [ "salesforce" ],
        "request_fingerprint" => SearchProfiles::ProfileBuilder.intent_fingerprint(simple_input)
      }
      token = CompiledPayloadToken.new.sign(payload)

      assert_equal payload, CompiledPayloadToken.new.verify_for!(token, simple_input:)

      error = assert_raises(SearchProfiles::IntentCompiler::Error) do
        CompiledPayloadToken.new.verify_for!(token, simple_input: simple_input.merge("technology_intent" => "java"))
      end

      assert_match "Gere novamente antes de salvar", error.message
    end
  end
end
