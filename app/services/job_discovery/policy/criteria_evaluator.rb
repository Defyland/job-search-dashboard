module JobDiscovery
  class Policy::CriteriaEvaluator
    def initialize(criteria:)
      @criteria = criteria
    end

    def potential_match?(title)
      normalized_title = normalize(title)
      return false if normalized_title.blank?

      !matches_any?(normalized_title, @criteria.negative_patterns) &&
        seniority?(normalized_title) &&
        title_language_match?(normalized_title) &&
        (title_stack_tags(normalized_title).any? || role_title?(normalized_title))
    end

    def classify(title:, remote_text:, location_text:, description:, source_slug:, posted_text:, published_at:)
      haystack = [ title, remote_text, location_text, description, posted_text ].join(" ")
      normalized_title = normalize(title)
      normalized_haystack = normalize(haystack)
      eligibility_flags = []

      return reject("vaga encerrada ou expirada") if normalized_haystack.match?(Policy::CLOSED_PATTERNS)

      if normalized_haystack.match?(Policy::WOMEN_ONLY_PATTERNS)
        return reject("vaga afirmativa para mulheres") unless @criteria.profile.include_women_only?

        eligibility_flags << "women_only"
      end

      return reject("titulo fora do escopo") if normalized_title.blank? || matches_any?(normalized_title, @criteria.negative_patterns)
      return reject("titulo sem senioridade") unless seniority?(normalized_title)
      return reject("titulo sem marcador de idioma do perfil") unless title_language_match?(normalized_title)

      title_tags = title_stack_tags(normalized_title)
      conflicting_title_tags = conflicting_title_stack_tags(normalized_title)
      return reject("titulo aponta para stack fora do perfil") if conflicting_title_tags.any?

      body_tags = title_tags.presence || context_stack_tags(normalized_haystack)
      return reject("sem stack alvo no titulo ou contexto imediato") if title_tags.blank? && body_tags.blank?
      return reject("sem foco tecnico compativel no titulo") unless role_title?(normalized_title) || title_tags.any?

      remote_signal = [ remote_text, location_text ].compact_blank.join(" ").presence || posted_text
      return reject("localidade sem sinal remoto compativel") if remote_blocked?(remote_signal, normalized_haystack, source_slug)

      classification =
        if title_tags.any?
          :strong
        elsif borderline_title_match?(normalized_title) && body_tags.any?
          :borderline
        else
          :rejected
        end

      return reject("sem match suficiente") if classification == :rejected

      Policy::Result.new(
        classification:,
        reason: build_reason(classification, title_tags.presence || body_tags, remote_signal, published_at),
        stack_tags: title_tags.presence || body_tags,
        score: build_score(classification, title_tags.present?, published_at),
        seniority: @criteria.profile.seniority_terms.first.presence || "senior",
        remote_signal: remote_signal.presence || "sem data publica",
        exclusion_reason: nil,
        search_profile: @criteria.profile,
        eligibility_flags:
      )
    end

    private
      def reject(reason)
        Policy.rejected_result(reason, profile: @criteria.profile)
      end

      def build_reason(classification, stack_tags, remote_signal, published_at)
        [
          @criteria.profile.name,
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

      def remote_blocked?(remote_signal, haystack, source_slug)
        return false unless @criteria.profile.required_remote?
        return false if source_slug == "programathor" && remote_signal.to_s.match?(Policy::REMOTE_PATTERNS)
        return true if remote_signal.to_s.match?(Policy::ONSITE_PATTERNS)
        return true if haystack.match?(Policy::ONSITE_PATTERNS) && !remote_match?(haystack)

        !(remote_match?(remote_signal.to_s) || remote_match?(haystack))
      end

      def remote_match?(text)
        text.to_s.match?(Policy::REMOTE_PATTERNS) || matches_any?(normalize(text), @criteria.location_patterns)
      end

      def seniority?(text)
        matches_any?(text, @criteria.seniority_patterns)
      end

      def role_title?(text)
        matches_any?(text, @criteria.role_patterns) || matches_any?(text, @criteria.title_patterns)
      end

      def borderline_title_match?(text)
        return role_title?(text) if @criteria.compiled_title_patterns.blank?

        matches_any?(text, @criteria.compiled_title_patterns)
      end

      def title_language_match?(text)
        return true if @criteria.language_scope == "both"

        matches_any?(text, @criteria.role_patterns)
      end

      def title_stack_tags(text)
        stack_tags(text, @criteria.title_stack_patterns)
      end

      def conflicting_title_stack_tags(text)
        stack_tags(text, @criteria.catalog_title_stack_patterns).reject do |tag|
          @criteria.allowed_catalog_stack_tags.include?(tag)
        end
      end

      def context_stack_tags(text)
        stack_tags(text, @criteria.context_stack_patterns)
      end

      def stack_tags(text, patterns_by_tag)
        patterns_by_tag.each_with_object([]) do |(tag, patterns), result|
          result << tag if patterns.any? { |pattern| text.match?(pattern) }
        end
      end

      def matches_any?(text, patterns)
        patterns.any? { |pattern| text.match?(pattern) }
      end

      def normalize(value)
        value.to_s.downcase.squish
      end
  end
end
