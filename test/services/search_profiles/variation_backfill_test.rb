require "test_helper"

module SearchProfiles
  class VariationBackfillTest < ActiveSupport::TestCase
    STACKS = [ "ruby", "ruby on rails", "react", "react native", "salesforce", "elixir", "golang" ].freeze
    TRUNCATED_STACKS = STACKS.first(6).freeze

    setup do
      @profile = users(:one).search_profiles.create!(
        name: "Senior Ruby/Rails/React/Salesforce Remote",
        target_stacks: TRUNCATED_STACKS,
        target_titles: [ "custom platform title" ],
        seniority_terms: [ "staff" ],
        location_terms: [ "custom location" ],
        negative_terms: [ "intern" ],
        required_remote: false,
        language_scope: :both,
        settings: {
          "intent" => {
            "technology_intent" => STACKS.join(", "),
            "seniority_preset" => "senior",
            "language_scope" => "both",
            "required_remote" => true,
            "region_scope" => "brazil_latam",
            "include_women_only" => false
          },
          "compiler" => {
            "stack_aliases" => {},
            "generated_titles" => { "pt" => [], "en" => [] }
          }
        }
      )
    end

    test "dry-run reports recovered stacks without persisting changes" do
      result = VariationBackfill.new(profile: @profile).call

      assert_equal :dry_run, result.status
      assert_equal [ "golang" ], result.added_stacks
      assert_equal STACKS, result.after_stacks
      assert_equal TRUNCATED_STACKS, @profile.reload.target_stacks
    end

    test "apply regenerates variations from stored intent without changing filters" do
      result = VariationBackfill.new(profile: @profile, apply: true).call
      @profile.reload

      assert_equal :updated, result.status
      assert_equal STACKS, @profile.target_stacks
      assert_includes @profile.target_titles, "custom platform title"
      assert_includes @profile.target_titles, "desenvolvedor elixir"
      assert_includes @profile.target_titles, "golang developer"
      assert_includes @profile.compiler_stack_aliases.fetch("elixir"), "phoenix"
      assert_includes @profile.compiler_stack_aliases.fetch("golang"), "go"
      assert_equal [ "staff" ], @profile.seniority_terms
      assert_equal [ "custom location" ], @profile.location_terms
      assert_equal [ "intern" ], @profile.negative_terms
      refute @profile.required_remote?
    end

    test "skips profiles without a stored technology intent" do
      @profile.update!(settings: {})

      result = VariationBackfill.new(profile: @profile, apply: true).call

      assert_equal :skipped, result.status
      assert_equal TRUNCATED_STACKS, @profile.reload.target_stacks
    end
  end
end
