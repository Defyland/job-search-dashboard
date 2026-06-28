require "test_helper"

module SearchProfiles
  class HeuristicIntentCompilerTest < ActiveSupport::TestCase
    test "builds canonical stacks and title variants from a simple intent" do
      payload = HeuristicIntentCompiler.new.call(
        technology_intent: "Java / React, Next.js",
        seniority_preset: "senior",
        language_scope: "both",
        required_remote: true,
        region_scope: "brazil_latam",
        include_women_only: false
      )

      assert_equal [ "java", "react", "nextjs" ], payload.fetch("canonical_stacks")
      assert_includes payload.fetch("title_variants_pt"), "desenvolvedor java"
      assert_includes payload.fetch("title_variants_en"), "react developer"
      assert_equal "heuristic", payload.fetch("provider")
      assert_equal "local-rules-v1", payload.fetch("model")
    end

    test "rejects empty technology intents" do
      error = assert_raises(SearchProfiles::IntentCompiler::Error) do
        HeuristicIntentCompiler.new.call(
          technology_intent: "   ",
          seniority_preset: "senior",
          language_scope: "both",
          required_remote: true,
          region_scope: "brazil_latam",
          include_women_only: false
        )
      end

      assert_equal "Informe ao menos a stack principal do perfil.", error.message
    end

    test "rejects punctuation-only technology intents" do
      error = assert_raises(SearchProfiles::IntentCompiler::Error) do
        HeuristicIntentCompiler.new.call(
          technology_intent: "### / +++",
          seniority_preset: "senior",
          language_scope: "both",
          required_remote: true,
          region_scope: "brazil_latam",
          include_women_only: false
        )
      end

      assert_equal "Informe ao menos a stack principal do perfil.", error.message
    end

    test "uses selected junior and pleno labels in generated profile names" do
      junior_payload = HeuristicIntentCompiler.new.call(
        technology_intent: "Java",
        seniority_preset: "junior",
        language_scope: "both",
        required_remote: true,
        region_scope: "brazil_latam",
        include_women_only: false
      )
      mid_payload = HeuristicIntentCompiler.new.call(
        technology_intent: "Java",
        seniority_preset: "mid",
        language_scope: "both",
        required_remote: true,
        region_scope: "brazil_latam",
        include_women_only: false
      )

      assert_equal "Junior Java Remote Brasil e LatAm", junior_payload.fetch("profile_name_suggestion")
      assert_equal "Pleno Java Remote Brasil e LatAm", mid_payload.fetch("profile_name_suggestion")
    end
  end
end
