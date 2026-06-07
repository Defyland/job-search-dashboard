module JobDiscovery
  class Policy
    Result = Struct.new(
      :classification,
      :reason,
      :stack_tags,
      :score,
      :seniority,
      :remote_signal,
      :exclusion_reason,
      :search_profile,
      :eligibility_flags,
      keyword_init: true
    ) do
      def accepted?
        classification.in?(%i[ strong borderline ])
      end
    end

    STACK_SYNONYMS = {
      ".net" => [ ".net", "dotnet", "c#", "asp.net" ],
      "c#" => [ "c#", ".net", "dotnet", "asp.net" ],
      "java" => [ "java", "spring", "spring boot", "jvm" ],
      "ruby on rails" => [ "ruby on rails", "rails" ],
      "rails" => [ "rails", "ruby on rails" ],
      "react" => [ "react", "reactjs", "react.js" ],
      "react native" => [ "react native", "react-native" ]
    }.freeze
    DEFAULT_PROFILE_NAME = "Default senior Ruby/Rails/React".freeze
    PORTUGUESE_ROLE_TERMS = [
      "engenheiro de software",
      "engenheira de software",
      "engenheiro",
      "engenheira",
      "desenvolvedor",
      "desenvolvedora",
      "consultor",
      "consultora",
      "analista",
      "arquiteto",
      "arquiteta"
    ].freeze
    ENGLISH_ROLE_TERMS = [
      "software engineer",
      "engineer",
      "developer",
      "consultant",
      "architect"
    ].freeze
    NEUTRAL_ROLE_TERMS = [
      "frontend",
      "front-end",
      "backend",
      "back-end",
      "fullstack",
      "full-stack",
      "dev"
    ].freeze
    ONSITE_PATTERNS = /\b(presencial|on[-\s]?site|h[ií]brido|hybrid)\b/i
    REMOTE_PATTERNS = /\b(remot[oa]?|remote|home[\s-]?office|brasil|brazil|latam)\b/i
    WOMEN_ONLY_PATTERNS = /
      (
        (vaga|oportunidade|banco\s+de\s+talentos).{0,80}(mulher(?:es)?|women)
        |(afirmativ[ao]s?|exclusiv[ao]s?|preferencial(?:mente)?).{0,60}(mulher(?:es)?|women)
        |(mulher(?:es)?|women).{0,60}(afirmativ[ao]s?|exclusiv[ao]s?|preferencial(?:mente)?|only)
        |women[-\s]?only
        |only\s+women
        |female[-\s]?only
      )
    /ix
    CLOSED_PATTERNS = /\b(expirad[ao]|encerrad[ao]|indispon[ií]vel|closed|expired|unavailable|vencida)\b/i

    DefaultProfile = Struct.new(
      :id,
      :name,
      :target_stacks,
      :target_titles,
      :seniority_terms,
      :location_terms,
      :negative_terms,
      :language_scope,
      :required_remote,
      :include_women_only,
      keyword_init: true
    ) do
      def required_remote?
        required_remote
      end

      def include_women_only?
        include_women_only
      end

      def policy_contract
        {
          profile_id: id,
          profile_name: name,
          seniority_terms: seniority_terms,
          stack_terms: target_stacks,
          title_terms: target_titles,
          language_scope: language_scope,
          location_terms: location_terms,
          required_remote: required_remote?,
          include_women_only: include_women_only?,
          exclude_terms: negative_terms + [ "mulheres", "women only", "female only" ],
          output: "POST accepted strong/borderline jobs and useful rejections to /api/v1/job_ingestions"
        }
      end
    end

    Criteria = Struct.new(
      :profile,
      :language_scope,
      :stack_patterns,
      :title_patterns,
      :role_patterns,
      :seniority_patterns,
      :location_patterns,
      :negative_patterns,
      keyword_init: true
    )

    def self.contract(search_profile: nil)
      if search_profile
        search_profile.policy_contract
      else
        profiles = SearchProfile.active.ordered.to_a
        return default_profile.policy_contract if profiles.blank?

        {
          profiles: profiles.map(&:policy_contract),
          output: "POST accepted strong/borderline jobs and useful rejections to /api/v1/job_ingestions"
        }
      end
    end

    def self.default_profile
      DefaultProfile.new(
        id: nil,
        name: DEFAULT_PROFILE_NAME,
        target_stacks: SearchProfile::DEFAULT_TARGET_STACKS,
        target_titles: SearchProfile::DEFAULT_TARGET_TITLES,
        seniority_terms: SearchProfile::DEFAULT_SENIORITY_TERMS,
        location_terms: SearchProfile::DEFAULT_LOCATION_TERMS,
        negative_terms: SearchProfile::DEFAULT_NEGATIVE_TERMS,
        language_scope: "both",
        required_remote: true,
        include_women_only: false
      )
    end

    def initialize(search_profile: nil, search_profiles: nil)
      @profiles =
        if search_profile
          [ search_profile ]
        elsif search_profiles
          Array(search_profiles)
        else
          SearchProfile.active.ordered.to_a
        end.presence || [ self.class.default_profile ]

      @criteria = @profiles.map { |profile| build_criteria(profile) }
    end

    def potential_match?(title)
      normalized_title = normalize(title)
      return false if normalized_title.blank?

      @criteria.any? do |criteria|
        !matches_any?(normalized_title, criteria.negative_patterns) &&
          seniority?(normalized_title, criteria) &&
          title_language_match?(normalized_title, criteria) &&
          (title_stack_tags(normalized_title, criteria).any? || role_title?(normalized_title, criteria))
      end
    end

    def classify(title:, remote_text:, location_text:, description:, source_slug:, posted_text:, published_at:)
      decisions = @criteria.map do |criteria|
        classify_for_criteria(criteria:, title:, remote_text:, location_text:, description:, source_slug:, posted_text:, published_at:)
      end

      decisions.select(&:accepted?).max_by(&:score) || decisions.max_by(&:score) || reject("perfil de busca indisponivel")
    end

    private
      def classify_for_criteria(criteria:, title:, remote_text:, location_text:, description:, source_slug:, posted_text:, published_at:)
        haystack = [ title, remote_text, location_text, description, posted_text ].join(" ")
        normalized_title = normalize(title)
        normalized_haystack = normalize(haystack)
        eligibility_flags = []

        return reject("vaga encerrada ou expirada", criteria.profile) if normalized_haystack.match?(CLOSED_PATTERNS)

        if normalized_haystack.match?(WOMEN_ONLY_PATTERNS)
          return reject("vaga afirmativa para mulheres", criteria.profile) unless criteria.profile.include_women_only?

          eligibility_flags << "women_only"
        end

        return reject("titulo fora do escopo", criteria.profile) if normalized_title.blank? || matches_any?(normalized_title, criteria.negative_patterns)
        return reject("titulo sem senioridade", criteria.profile) unless seniority?(normalized_title, criteria)
        return reject("titulo sem marcador de idioma do perfil", criteria.profile) unless title_language_match?(normalized_title, criteria)

        title_tags = title_stack_tags(normalized_title, criteria)
        body_tags = title_tags.presence || stack_tags(normalized_haystack, criteria)
        return reject("sem stack alvo no titulo ou contexto imediato", criteria.profile) if title_tags.blank? && body_tags.blank?
        return reject("sem foco tecnico compativel no titulo", criteria.profile) unless role_title?(normalized_title, criteria) || title_tags.any?

        remote_signal = [ remote_text, location_text ].compact_blank.join(" ").presence || posted_text
        return reject("localidade sem sinal remoto compativel", criteria.profile) if remote_blocked?(remote_signal, normalized_haystack, source_slug, criteria)

        classification =
          if title_tags.any?
            :strong
          elsif role_title?(normalized_title, criteria) && body_tags.any?
            :borderline
          else
            :rejected
          end

        return reject("sem match suficiente", criteria.profile) if classification == :rejected

        Result.new(
          classification:,
          reason: build_reason(classification, title_tags.presence || body_tags, remote_signal, published_at, criteria.profile),
          stack_tags: title_tags.presence || body_tags,
          score: build_score(classification, title_tags.present?, published_at),
          seniority: criteria.profile.seniority_terms.first.presence || "senior",
          remote_signal: remote_signal.presence || "sem data publica",
          exclusion_reason: nil,
          search_profile: criteria.profile,
          eligibility_flags:
        )
      end

      def reject(reason, profile = nil)
        Result.new(
          classification: :rejected,
          reason:,
          stack_tags: [],
          score: 0,
          seniority: profile&.seniority_terms&.first.presence || "senior",
          remote_signal: nil,
          exclusion_reason: reason,
          search_profile: profile,
          eligibility_flags: []
        )
      end

      def build_reason(classification, stack_tags, remote_signal, published_at, profile)
        [
          profile.name,
          classification == :strong ? "titulo forte" : "titulo tecnico com stack no contexto",
          stack_tags.join(", "),
          remote_signal.presence || "sem sinal remoto explicito",
          published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica"
        ].join(" | ")
      end

      def build_score(classification, title_stack_present, published_at)
        base_score = classification == :strong ? 92 : 78
        base_score += 4 if title_stack_present
        base_score += 4 if published_at.present? && published_at >= 7.days.ago
        base_score += 2 if published_at.present? && published_at >= 24.hours.ago
        [ base_score, 99 ].min
      end

      def remote_blocked?(remote_signal, haystack, source_slug, criteria)
        return false unless criteria.profile.required_remote?
        return false if source_slug == "programathor" && remote_signal.to_s.match?(REMOTE_PATTERNS)
        return true if remote_signal.to_s.match?(ONSITE_PATTERNS)
        return true if haystack.match?(ONSITE_PATTERNS) && !remote_match?(haystack, criteria)

        !(remote_match?(remote_signal.to_s, criteria) || remote_match?(haystack, criteria))
      end

      def remote_match?(text, criteria)
        text.to_s.match?(REMOTE_PATTERNS) || matches_any?(normalize(text), criteria.location_patterns)
      end

      def seniority?(text, criteria)
        matches_any?(text, criteria.seniority_patterns)
      end

      def role_title?(text, criteria)
        matches_any?(text, criteria.role_patterns) || matches_any?(text, criteria.title_patterns)
      end

      def title_language_match?(text, criteria)
        return true if criteria.language_scope == "both"

        matches_any?(text, criteria.role_patterns)
      end

      def title_stack_tags(text, criteria)
        stack_tags(text, criteria)
      end

      def stack_tags(text, criteria)
        criteria.stack_patterns.each_with_object([]) do |(tag, patterns), result|
          result << tag if patterns.any? { |pattern| text.match?(pattern) }
        end
      end

      def matches_any?(text, patterns)
        patterns.any? { |pattern| text.match?(pattern) }
      end

      def build_criteria(profile)
        language_scope = profile_language_scope(profile)

        Criteria.new(
          profile:,
          language_scope:,
          stack_patterns: build_stack_patterns(profile.target_stacks),
          title_patterns: build_patterns(profile.target_titles),
          role_patterns: build_patterns(role_terms_for(language_scope)),
          seniority_patterns: build_patterns(profile.seniority_terms),
          location_patterns: build_patterns(profile.location_terms),
          negative_patterns: build_patterns(profile.negative_terms)
        )
      end

      def profile_language_scope(profile)
        profile.respond_to?(:language_scope) ? profile.language_scope.to_s.presence || "both" : "both"
      end

      def role_terms_for(language_scope)
        case language_scope
        when "portuguese"
          PORTUGUESE_ROLE_TERMS + NEUTRAL_ROLE_TERMS
        when "english"
          ENGLISH_ROLE_TERMS + NEUTRAL_ROLE_TERMS
        else
          PORTUGUESE_ROLE_TERMS + ENGLISH_ROLE_TERMS + NEUTRAL_ROLE_TERMS
        end
      end

      def build_stack_patterns(target_stacks)
        normalize_list(target_stacks).each_with_object({}) do |tag, result|
          terms = STACK_SYNONYMS.fetch(tag, [ tag ])
          result[tag] = build_patterns(terms)
        end
      end

      def build_patterns(terms)
        normalize_list(terms).map { |term| term_pattern(term) }
      end

      def term_pattern(term)
        escaped = Regexp.escape(term).gsub("\\ ", "[\\s-]+")
        /(?<![[:alnum:]])#{escaped}(?![[:alnum:]])/i
      end

      def normalize_list(values)
        Array(values).flat_map { |value| value.to_s.split(",") }
                     .map { |value| normalize(value) }
                     .reject(&:blank?)
                     .uniq
      end

      def normalize(value)
        value.to_s.downcase.squish
      end
  end
end
