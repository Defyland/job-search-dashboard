module SearchProfiles
  class HeuristicIntentCompiler
    STACK_DISPLAY_LABELS = {
      ".net" => ".NET",
      "c#" => "C#",
      "java" => "Java",
      "ruby" => "Ruby",
      "ruby on rails" => "Ruby on Rails",
      "rails" => "Rails",
      "react" => "React",
      "react native" => "React Native",
      "nextjs" => "Next.js",
      "salesforce" => "Salesforce",
      "servicenow" => "ServiceNow",
      "recruiter" => "Recruiter",
      "rh" => "RH"
    }.freeze

    STACK_CANONICAL_ALIASES = {
      "dotnet" => ".net",
      "asp.net" => ".net",
      "csharp" => "c#",
      "reactjs" => "react",
      "react.js" => "react",
      "react-native" => "react native",
      "rn" => "react native",
      "next.js" => "nextjs",
      "next js" => "nextjs",
      "ror" => "ruby on rails",
      "service now" => "servicenow",
      "tech recruiter" => "recruiter",
      "technical recruiter" => "recruiter",
      "talent acquisition" => "recruiter",
      "recrutador" => "recruiter",
      "recrutadora" => "recruiter",
      "recrutamento" => "recruiter",
      "recrutamento e selecao" => "recruiter",
      "recrutamento e seleção" => "recruiter",
      "hr" => "rh",
      "hrbp" => "rh",
      "human resources" => "rh",
      "recursos humanos" => "rh",
      "people ops" => "rh",
      "people operations" => "rh",
      "people partner" => "rh"
    }.freeze

    PROVIDER = "heuristic".freeze
    MODEL = "local-rules-v1".freeze

    def call(technology_intent:, seniority_preset:, language_scope:, required_remote:, region_scope:, include_women_only:)
      canonical_stacks = detect_canonical_stacks(technology_intent)
      raise SearchProfiles::IntentCompiler::Error, "Informe ao menos a stack principal do perfil." if canonical_stacks.blank?

      {
        "profile_name_suggestion" => profile_name_for(canonical_stacks, seniority_preset, required_remote, region_scope),
        "canonical_stacks" => canonical_stacks,
        "title_variants_pt" => title_variants_for(canonical_stacks, :pt),
        "title_variants_en" => title_variants_for(canonical_stacks, :en),
        "stack_aliases" => stack_aliases_for(canonical_stacks),
        "provider" => PROVIDER,
        "model" => MODEL
      }
    end

    private
      def detect_canonical_stacks(technology_intent)
        normalized_intent = SearchProfiles::Vocabulary.normalize(technology_intent)
        return [] if normalized_intent.blank?

        explicit = explicit_stack_tokens(technology_intent).filter_map { |token| explicit_canonical_stack_for(token) }
        detected = detected_catalog_stacks(normalized_intent)

        merged_stacks(explicit, detected)
      end

      def detected_catalog_stacks(normalized_intent)
        JobDiscovery::Policy::TITLE_STACK_SYNONYMS.filter_map do |stack, synonyms|
          patterns = SearchProfiles::Vocabulary.normalize_list([ stack ] + Array(synonyms))
          match_index = patterns.filter_map { |term| term_match_index(normalized_intent, term) }.min
          [ stack, match_index ] if match_index
        end.sort_by { |_stack, match_index| match_index }
          .map(&:first)
      end

      def explicit_stack_tokens(technology_intent)
        technology_intent.to_s.tr("/", ",").split(/[\n,;+]/)
                         .map { |token| SearchProfiles::Vocabulary.normalize(token) }
                         .select { |token| usable_stack_token?(token) }
      end

      def usable_stack_token?(token)
        token.match?(/[[:alnum:]]/)
      end

      def matches_term?(input, term)
        pattern = Regexp.escape(term).gsub("\\ ", "[\\s-]+")
        input.match?(/(?<![[:alnum:]])#{pattern}(?![[:alnum:]])/i)
      end

      def term_match_index(input, term)
        pattern = Regexp.escape(term).gsub("\\ ", "[\\s-]+")
        input.to_enum(:scan, /(?<![[:alnum:]])#{pattern}(?![[:alnum:]])/i).map { Regexp.last_match.begin(0) }.min
      end

      def canonical_stack_for(token)
        normalized_token = SearchProfiles::Vocabulary.normalize(token)
        STACK_CANONICAL_ALIASES.fetch(normalized_token) do
          JobDiscovery::Policy::TITLE_STACK_SYNONYMS.key?(normalized_token) ? normalized_token : normalized_token
        end
      end

      def explicit_canonical_stack_for(token)
        canonical_stack = canonical_stack_for(token)
        return canonical_stack if known_stack?(canonical_stack)
        return canonical_stack unless canonical_stack.include?(" ")

        nil
      end

      def merged_stacks(explicit, detected)
        accepted = []

        SearchProfiles::Vocabulary.normalize_list(explicit + detected).each do |candidate|
          next if duplicate_stack?(accepted, candidate)

          accepted << candidate
        end

        accepted.first(6)
      end

      def duplicate_stack?(accepted, candidate)
        accepted.include?(candidate) || accepted.any? { |existing| overlapping_stack_group?(existing, candidate) }
      end

      def overlapping_stack_group?(left, right)
        stack_terms_for(left).include?(right) || stack_terms_for(right).include?(left)
      end

      def known_stack?(stack)
        JobDiscovery::Policy::TITLE_STACK_SYNONYMS.key?(stack) || STACK_DISPLAY_LABELS.key?(stack)
      end

      def stack_terms_for(stack)
        SearchProfiles::Vocabulary.normalize_list(JobDiscovery::Policy::TITLE_STACK_SYNONYMS.fetch(stack, [ stack ]))
      end

      def profile_name_for(canonical_stacks, seniority_preset, required_remote, region_scope)
        seniority_label = SearchProfiles::Vocabulary::SENIORITY_PRESET_LABELS.fetch(
          SearchProfiles::Vocabulary.normalize_seniority_preset(seniority_preset)
        )
        stack_label = canonical_stacks.map { |stack| display_label_for(stack) }.join("/")
        location_suffix = SearchProfiles::Vocabulary::BOOLEAN.cast(required_remote) ? " Remote #{region_label_for(region_scope)}" : ""

        "#{seniority_label} #{stack_label}#{location_suffix}".squish
      end

      def region_label_for(region_scope)
        SearchProfiles::Vocabulary::REGION_SCOPE_LABELS.fetch(
          SearchProfiles::Vocabulary.normalize_region_scope(region_scope)
        )
      end

      def title_variants_for(canonical_stacks, language)
        canonical_stacks.flat_map do |stack|
          next non_tech_title_variants_for(stack, language) if SearchProfiles::Vocabulary.non_tech_role_stack?([ stack ])

          stack_label = display_label_for(stack)

          case language
          when :pt
            portuguese_titles_for(stack_label)
          else
            english_titles_for(stack_label)
          end
        end.map { |title| SearchProfiles::Vocabulary.normalize(title) }
          .uniq
          .first(12)
      end

      def non_tech_title_variants_for(stack, language)
        language_scope = language == :pt ? "portuguese" : "english"

        SearchProfiles::Vocabulary.role_titles_for(language_scope, target_stacks: [ stack ])
      end

      def portuguese_titles_for(stack_label)
        [
          "desenvolvedor #{stack_label}",
          "engenheiro #{stack_label}",
          "engenheiro de software #{stack_label}"
        ]
      end

      def english_titles_for(stack_label)
        [
          "#{stack_label} developer",
          "#{stack_label} engineer",
          "#{stack_label} software engineer"
        ]
      end

      def stack_aliases_for(canonical_stacks)
        canonical_stacks.map do |stack|
          {
            "canonical_stack" => stack,
            "aliases" => SearchProfiles::Vocabulary.normalize_list(
              JobDiscovery::Policy::TITLE_STACK_SYNONYMS.fetch(stack, [ stack ])
            )
          }
        end
      end

      def display_label_for(stack)
        STACK_DISPLAY_LABELS.fetch(stack) { stack.to_s.split.map(&:capitalize).join(" ") }
      end
  end
end
