require "test_helper"

class SearchProfiles::IntentCompilerTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls

    def initialize(response:, error: nil, model: "claude-sonnet-4-20250514")
      @response = response
      @error = error
      @model = model
      @calls = 0
    end

    def model
      @model
    end

    def provider_name
      "anthropic"
    end

    def create_structured_output(**)
      @calls += 1
      raise @error if @error

      @response
    end
  end

  test "normalizes a structured compiler response" do
    compiler = SearchProfiles::IntentCompiler.new(
      client: FakeClient.new(
        response: {
          "profile_name_suggestion" => "Senior ServiceNow Remote",
          "canonical_stacks" => [ "ServiceNow ", "servicenow" ],
          "title_variants_pt" => [ " Desenvolvedor ServiceNow ", "Consultor ServiceNow" ],
          "title_variants_en" => [ "ServiceNow Developer" ],
          "stack_aliases" => [
            {
              "canonical_stack" => "servicenow",
              "aliases" => [ "ITSM", "Flow Designer", "itsm" ]
            }
          ]
        }
      )
    )

    result = compiler.call(
      technology_intent: "ServiceNow",
      seniority_preset: "senior",
      language_scope: "both",
      required_remote: true,
      region_scope: "brazil_latam",
      include_women_only: false
    )

    assert_equal [ "servicenow" ], result["canonical_stacks"]
    assert_equal [ "desenvolvedor servicenow", "consultor servicenow" ], result["title_variants_pt"]
    assert_equal "claude-sonnet-4-20250514", result["model"]
    assert_equal "anthropic", result["provider"]
    assert_equal [ "itsm", "flow designer" ], result["stack_aliases"].first["aliases"]
  end

  test "retries a transient client error once" do
    transient_error = SearchProfiles::CompilerClient::TransientError.new("timeout")
    client = FakeClient.new(response: nil, error: transient_error)
    compiler = SearchProfiles::IntentCompiler.new(client:)

    assert_raises(SearchProfiles::IntentCompiler::Error) do
      compiler.call(
        technology_intent: "Java",
        seniority_preset: "senior",
        language_scope: "both",
        required_remote: true,
        region_scope: "brazil_latam",
        include_women_only: false
      )
    end

    assert_equal 2, client.calls
  end
end
