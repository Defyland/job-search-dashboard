module SearchProfiles
  class IntentCompiler
    class Error < StandardError; end

    OUTPUT_SCHEMA = {
      type: "object",
      properties: {
        profile_name_suggestion: { type: "string" },
        canonical_stacks: {
          type: "array",
          items: { type: "string" },
          minItems: 1,
          maxItems: 6
        },
        title_variants_pt: {
          type: "array",
          items: { type: "string" },
          maxItems: 12
        },
        title_variants_en: {
          type: "array",
          items: { type: "string" },
          maxItems: 12
        },
        stack_aliases: {
          type: "array",
          items: {
            type: "object",
            properties: {
              canonical_stack: { type: "string" },
              aliases: {
                type: "array",
                items: { type: "string" },
                maxItems: 12
              }
            },
            required: %w[canonical_stack aliases],
            additionalProperties: false
          },
          maxItems: 6
        }
      },
      required: %w[profile_name_suggestion canonical_stacks title_variants_pt title_variants_en stack_aliases],
      additionalProperties: false
    }.freeze

    def initialize(client: SearchProfiles::CompilerClient.new)
      @client = client
    end

    def call(technology_intent:, seniority_preset:, language_scope:, required_remote:, region_scope:, include_women_only:)
      raise Error, "Informe ao menos a stack principal do perfil." if technology_intent.to_s.squish.blank?

      response = with_retry do
        @client.create_structured_output(
          input: prompt_input(
            technology_intent:,
            seniority_preset:,
            language_scope:,
            required_remote:,
            region_scope:,
            include_women_only:
          ),
          schema_name: "search_profile_intent",
          schema: OUTPUT_SCHEMA
        )
      end

      normalize_response(response).merge(
        "model" => @client.model,
        "provider" => @client.provider_name
      )
    rescue SearchProfiles::CompilerClient::ConfigurationError, SearchProfiles::CompilerClient::Error => error
      raise Error, error.message
    end

    private
      def with_retry
        attempts = 0

        begin
          attempts += 1
          yield
        rescue SearchProfiles::CompilerClient::TransientError => error
          retry if attempts < 2

          raise Error, error.message
        end
      end

      def prompt_input(technology_intent:, seniority_preset:, language_scope:, required_remote:, region_scope:, include_women_only:)
        [
          {
            role: "system",
            content: <<~PROMPT.squish
              You compile job-search intents into canonical stacks, realistic hands-on job-title variants, and useful technical aliases.
              Focus on software-engineering roles, not management-only roles. Keep outputs concise and market-realistic.
              Do not include company names, location names, remote markers, salary, seniority adjectives beyond the requested level,
              or generic soft-skill phrasing inside titles. Prefer titles that appear in Brazilian and international tech hiring markets.
            PROMPT
          },
          {
            role: "user",
            content: {
              technology_intent: technology_intent.to_s,
              seniority_preset: seniority_preset.to_s,
              language_scope: language_scope.to_s,
              required_remote: ActiveModel::Type::Boolean.new.cast(required_remote),
              region_scope: region_scope.to_s,
              include_women_only: ActiveModel::Type::Boolean.new.cast(include_women_only),
              instructions: [
                "Return canonical stack labels in lowercase.",
                "Return title_variants_pt in Portuguese only.",
                "Return title_variants_en in English only.",
                "Include only hands-on titles that make sense for the requested stack.",
                "Aliases must help identify the stack in titles or short descriptions."
              ]
            }.to_json
          }
        ]
      end

      def normalize_response(response)
        canonical_stacks = normalize_list(response["canonical_stacks"])
        raise Error, "O Claude nao retornou stacks canonicas suficientes." if canonical_stacks.blank?

        stack_aliases =
          Array(response["stack_aliases"]).each_with_object([]) do |entry, result|
            canonical_stack = entry["canonical_stack"].to_s.downcase.squish
            aliases = normalize_list(entry["aliases"])
            next if canonical_stack.blank?

            result << {
              "canonical_stack" => canonical_stack,
              "aliases" => aliases
            }
          end

        {
          "profile_name_suggestion" => response["profile_name_suggestion"].to_s.squish,
          "canonical_stacks" => canonical_stacks,
          "title_variants_pt" => normalize_list(response["title_variants_pt"]),
          "title_variants_en" => normalize_list(response["title_variants_en"]),
          "stack_aliases" => stack_aliases
        }
      end

      def normalize_list(values)
        Array(values).map { |value| value.to_s.downcase.squish }.reject(&:blank?).uniq
      end
  end
end
