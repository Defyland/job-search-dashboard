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

      assert_equal "Informe ao menos a area, cargo ou stack principal do perfil.", error.message
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

      assert_equal "Informe ao menos a area, cargo ou stack principal do perfil.", error.message
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

    test "builds recruiter and hr role profiles" do
      recruiter_payload = HeuristicIntentCompiler.new.call(
        technology_intent: "tech recruiter",
        seniority_preset: "senior",
        language_scope: "both",
        required_remote: true,
        region_scope: "brazil_latam",
        include_women_only: false
      )
      hr_payload = HeuristicIntentCompiler.new.call(
        technology_intent: "recursos humanos",
        seniority_preset: "senior",
        language_scope: "both",
        required_remote: true,
        region_scope: "brazil_latam",
        include_women_only: false
      )

      assert_equal [ "recruiter" ], recruiter_payload.fetch("canonical_stacks")
      assert_includes recruiter_payload.fetch("title_variants_pt"), "recrutadora"
      assert_includes recruiter_payload.fetch("title_variants_en"), "technical recruiter"
      assert_equal [ "rh" ], hr_payload.fetch("canonical_stacks")
      assert_includes hr_payload.fetch("title_variants_pt"), "analista de rh"
      assert_includes hr_payload.fetch("title_variants_en"), "human resources specialist"
    end

    test "builds common non technical role profiles" do
      cases = {
        "product manager" => [ "product", "gerente de produto", "product manager" ],
        "marketing" => [ "marketing", "analista de marketing", "marketing manager" ],
        "account executive" => [ "sales", "executivo de contas", "account executive" ],
        "designer" => [ "design", "product designer", "ux designer" ],
        "customer success" => [ "customer_success", "analista de customer success", "customer success manager" ],
        "finance" => [ "finance", "analista financeiro", "financial analyst" ],
        "operations" => [ "operations", "analista de operacoes", "operations analyst" ],
        "project manager" => [ "project_management", "gerente de projetos", "project manager" ],
        "data analyst" => [ "data", "analista de dados", "data analyst" ]
      }

      cases.each do |intent, (canonical_stack, portuguese_title, english_title)|
        payload = HeuristicIntentCompiler.new.call(
          technology_intent: intent,
          seniority_preset: "senior",
          language_scope: "both",
          required_remote: true,
          region_scope: "brazil_latam",
          include_women_only: false
        )

        assert_equal [ canonical_stack ], payload.fetch("canonical_stacks"), intent
        assert_includes payload.fetch("title_variants_pt"), portuguese_title, intent
        assert_includes payload.fetch("title_variants_en"), english_title, intent
      end
    end
  end
end
