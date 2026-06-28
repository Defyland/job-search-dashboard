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

    test "builds junior profile terms without excluding junior titles" do
      attributes = ProfileBuilder.from_compiled(
        simple_input: simple_input.merge("seniority_preset" => "junior"),
        compiled_payload: compiled_payload
      )

      assert_includes attributes[:seniority_terms], "junior"
      refute_includes attributes[:negative_terms], "junior"
      refute_includes attributes[:negative_terms], "júnior"
      assert_includes attributes[:negative_terms], "senior"
    end

    test "builds mid profile terms without excluding pleno titles" do
      attributes = ProfileBuilder.from_compiled(
        simple_input: simple_input.merge("seniority_preset" => "mid"),
        compiled_payload: compiled_payload
      )

      assert_includes attributes[:seniority_terms], "pleno"
      refute_includes attributes[:negative_terms], "pleno"
      refute_includes attributes[:negative_terms], "mid-level"
      assert_includes attributes[:negative_terms], "junior"
      assert_includes attributes[:negative_terms], "senior"
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

      def compiled_payload
        {
          "profile_name_suggestion" => "Java Remote",
          "canonical_stacks" => [ "java" ],
          "title_variants_pt" => [ "desenvolvedor java" ],
          "title_variants_en" => [ "java developer" ],
          "stack_aliases" => []
        }
      end
  end
end
