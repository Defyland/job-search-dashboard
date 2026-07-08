module JobDiscovery
  class Policy::CriteriaBuilder
    def self.catalog_title_stack_patterns
      @catalog_title_stack_patterns ||= Policy::TITLE_STACK_SYNONYMS.each_with_object({}) do |(tag, terms), result|
        result[tag] = build_patterns(terms)
      end
    end

    def self.build_patterns(terms)
      normalize_list(terms).map { |term| term_pattern(term) }
    end

    def self.normalize_list(values)
      SearchProfiles::Vocabulary.normalize_list(values)
    end

    def self.term_pattern(term)
      escaped = Regexp.escape(term).gsub("\\ ", "[\\s-]+")
      /(?<![[:alnum:]])#{escaped}(?![[:alnum:]])/i
    end

    def initialize(profile:)
      @profile = profile
    end

    def call
      language_scope = profile_language_scope

      Policy::Criteria.new(
        profile: @profile,
        language_scope:,
        title_stack_patterns: build_stack_patterns(include_compiler_aliases: true),
        context_stack_patterns: build_stack_patterns(include_compiler_aliases: false),
        allowed_catalog_stack_tags: allowed_catalog_stack_tags,
        compiled_title_patterns: self.class.build_patterns(compiler_generated_titles(language_scope)),
        catalog_title_stack_patterns: self.class.catalog_title_stack_patterns,
        title_patterns: self.class.build_patterns(@profile.target_titles),
        role_patterns: self.class.build_patterns(role_terms_for(language_scope)),
        seniority_patterns: self.class.build_patterns(@profile.seniority_terms),
        location_patterns: self.class.build_patterns(@profile.location_terms),
        negative_patterns: self.class.build_patterns(@profile.negative_terms)
      )
    end

    private
      def profile_language_scope
        return SearchProfiles::Vocabulary::DEFAULT_LANGUAGE_SCOPE unless @profile.respond_to?(:language_scope)

        @profile.language_scope.to_s.presence || SearchProfiles::Vocabulary::DEFAULT_LANGUAGE_SCOPE
      end

      def role_terms_for(language_scope)
        if SearchProfiles::Vocabulary.non_tech_role_stack?(@profile.target_stacks)
          return SearchProfiles::Vocabulary.role_titles_for(language_scope, target_stacks: @profile.target_stacks)
        end

        case language_scope
        when "portuguese"
          Policy::PORTUGUESE_ROLE_TERMS + Policy::NEUTRAL_ROLE_TERMS
        when "english"
          Policy::ENGLISH_ROLE_TERMS + Policy::NEUTRAL_ROLE_TERMS
        else
          Policy::PORTUGUESE_ROLE_TERMS + Policy::ENGLISH_ROLE_TERMS + Policy::NEUTRAL_ROLE_TERMS
        end
      end

      def build_stack_patterns(include_compiler_aliases:)
        normalize_list(@profile.target_stacks).each_with_object({}) do |tag, result|
          terms = Policy::STACK_SYNONYMS.fetch(tag, [ tag ])

          if include_compiler_aliases && @profile.respond_to?(:compiler_stack_aliases)
            terms += Array(@profile.compiler_stack_aliases[tag])
          end

          result[tag] = self.class.build_patterns(terms)
        end
      end

      def allowed_catalog_stack_tags
        normalize_list(@profile.target_stacks).each_with_object([]) do |stack, result|
          result << stack if Policy::TITLE_STACK_SYNONYMS.key?(stack)
          result.concat(Policy::COMPATIBLE_TITLE_STACKS.fetch(stack, []))
        end.uniq
      end

      def compiler_generated_titles(language_scope)
        return [] unless @profile.respond_to?(:compiler_settings)

        generated_titles = @profile.compiler_settings.fetch("generated_titles", {})
        case language_scope
        when "portuguese"
          generated_titles.fetch("pt", [])
        when "english"
          generated_titles.fetch("en", [])
        else
          Array(generated_titles.fetch("pt", [])) + Array(generated_titles.fetch("en", []))
        end
      end

      def normalize_list(values)
        self.class.normalize_list(values)
      end
  end
end
