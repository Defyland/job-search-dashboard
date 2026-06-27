require "test_helper"

module SearchProfiles
  class ProfileBuilderTest < ActiveSupport::TestCase
    test "rejects compiled payload without canonical stacks" do
      error = assert_raises(SearchProfiles::IntentCompiler::Error) do
        ProfileBuilder.from_compiled(
          simple_input: simple_input,
          compiled_payload: {
            "profile_name_suggestion" => "Senior Remote",
            "canonical_stacks" => [],
            "title_variants_pt" => [],
            "title_variants_en" => [],
            "stack_aliases" => []
          }
        )
      end

      assert_equal "Informe ao menos a stack principal do perfil.", error.message
    end

    private
      def simple_input
        {
          "technology_intent" => "",
          "seniority_preset" => "senior",
          "language_scope" => "both",
          "required_remote" => "1",
          "region_scope" => "brazil_latam",
          "include_women_only" => "0",
          "scan_window_days" => "20"
        }
      end
  end
end
