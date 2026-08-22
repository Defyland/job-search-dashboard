module SearchProfiles
  class VariationBackfill
    Result = Data.define(:profile_id, :status, :before_stacks, :after_stacks) do
      def added_stacks
        after_stacks - before_stacks
      end
    end

    COMPILER_INPUT_KEYS = %w[
      technology_intent
      seniority_preset
      language_scope
      required_remote
      region_scope
      include_women_only
    ].freeze

    def initialize(profile:, apply: false, compiler: SearchProfiles::HeuristicIntentCompiler.new)
      @profile = profile
      @apply = apply
      @compiler = compiler
    end

    def call
      before_stacks = normalized_stacks(@profile.target_stacks)
      return result(:skipped, before_stacks, before_stacks) if stored_technology_intent.blank?

      simple_input = @profile.simple_form_state.deep_stringify_keys

      compiled_payload = @compiler.call(**compiler_input(simple_input))
      compiled_payload["request_fingerprint"] = SearchProfiles::ProfileBuilder.intent_fingerprint(simple_input)
      attributes = backfill_attributes(simple_input, compiled_payload)

      @profile.with_lock { @profile.update!(attributes) } if @apply

      result(@apply ? :updated : :dry_run, before_stacks, attributes.fetch(:target_stacks))
    end

    private
      def compiler_input(simple_input)
        simple_input.slice(*COMPILER_INPUT_KEYS).symbolize_keys
      end

      def backfill_attributes(simple_input, compiled_payload)
        SearchProfiles::ProfileBuilder.from_compiled(
          simple_input:,
          compiled_payload:,
          active: @profile.active?,
          existing_profile: @profile
        ).slice(:target_stacks, :target_titles, :settings)
      end

      def result(status, before_stacks, after_stacks)
        Result.new(
          profile_id: @profile.id,
          status:,
          before_stacks: normalized_stacks(before_stacks),
          after_stacks: normalized_stacks(after_stacks)
        )
      end

      def normalized_stacks(stacks)
        SearchProfiles::Vocabulary.normalize_list(stacks)
      end

      def stored_technology_intent
        @profile.intent_settings["technology_intent"]
      end
  end
end
