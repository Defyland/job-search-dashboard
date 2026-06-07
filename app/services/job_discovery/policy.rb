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
      keyword_init: true
    ) do
      def accepted?
        classification.in?(%i[ strong borderline ])
      end
    end

    STACK_PATTERNS = {
      "react native" => /\breact[\s-]*native\b/i,
      "ruby on rails" => /\bruby\s+on\s+rails\b|\brails\b/i,
      "react" => /\breact(?:js)?\b/i,
      "ruby" => /\bruby\b/i
    }.freeze
    SENIORITY_TERMS = %w[senior sênior sr staff].freeze
    STACK_TERMS = [ "ruby", "ruby on rails", "rails", "react", "react native", "frontend", "fullstack" ].freeze
    EXCLUDE_TERMS = [ "junior", "júnior", "pleno", "mid-level", "trainee", "intern", "internship", "estágio", "mulheres", "women only" ].freeze
    ROLE_PATTERNS = /\b(software engineer|engenheir[oa]\s+de\s+software|frontend|front-end|backend|back-end|full[\s-]?stack|developer|desenvolvedor(?:a)?)\b/i
    SENIORITY_PATTERNS = /\b(senior|sênior|sr\.?|staff)\b/i
    NEGATIVE_TITLE_PATTERNS = /\b(est[aá]gio|internship|intern|trainee|j[uú]nior|junior|pleno|mid(?:-|\s)?level)\b/i
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

    def self.contract
      {
        seniority_terms: SENIORITY_TERMS,
        stack_terms: STACK_TERMS,
        location_priority: "remote compatible with Brazil or LatAm",
        exclude_terms: EXCLUDE_TERMS,
        output: "POST accepted strong/borderline jobs and useful rejections to /api/v1/job_ingestions"
      }
    end

    def potential_match?(title)
      normalized_title = normalize(title)
      return false if normalized_title.blank?
      return false if normalized_title.match?(NEGATIVE_TITLE_PATTERNS)

      seniority?(normalized_title) && (title_stack_tags(normalized_title).any? || normalized_title.match?(ROLE_PATTERNS))
    end

    def classify(title:, remote_text:, location_text:, description:, source_slug:, posted_text:, published_at:)
      haystack = [ title, remote_text, location_text, description, posted_text ].join(" ")
      normalized_title = normalize(title)
      normalized_haystack = normalize(haystack)

      return reject("vaga encerrada ou expirada") if normalized_haystack.match?(CLOSED_PATTERNS)
      return reject("vaga afirmativa para mulheres") if normalized_haystack.match?(WOMEN_ONLY_PATTERNS)
      return reject("titulo fora do escopo") if normalized_title.blank? || normalized_title.match?(NEGATIVE_TITLE_PATTERNS)
      return reject("titulo sem senioridade") unless seniority?(normalized_title)

      title_tags = title_stack_tags(normalized_title)
      body_tags = title_tags.presence || stack_tags(normalized_haystack)
      return reject("sem stack alvo no titulo ou contexto imediato") if title_tags.blank? && body_tags.blank?
      return reject("sem foco tecnico compativel no titulo") unless normalized_title.match?(ROLE_PATTERNS) || title_tags.any?

      remote_signal = [ remote_text, location_text ].compact_blank.join(" ").presence || posted_text
      return reject("localidade sem sinal remoto compativel") if remote_blocked?(remote_signal, normalized_haystack, source_slug)

      classification =
        if title_tags.any?
          :strong
        elsif normalized_title.match?(ROLE_PATTERNS) && body_tags.any?
          :borderline
        else
          :rejected
        end

      return reject("sem match suficiente") if classification == :rejected

      Result.new(
        classification:,
        reason: build_reason(classification, title_tags.presence || body_tags, remote_signal, published_at),
        stack_tags: title_tags.presence || body_tags,
        score: build_score(classification, title_tags.present?, published_at),
        seniority: "senior",
        remote_signal: remote_signal.presence || "sem data publica",
        exclusion_reason: nil
      )
    end

    private
      def reject(reason)
        Result.new(classification: :rejected, reason:, stack_tags: [], score: 0, seniority: "senior", remote_signal: nil, exclusion_reason: reason)
      end

      def build_reason(classification, stack_tags, remote_signal, published_at)
        [
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
        return false if source_slug == "programathor" && remote_signal.to_s.match?(REMOTE_PATTERNS)
        return true if remote_signal.to_s.match?(ONSITE_PATTERNS)
        return true if haystack.match?(ONSITE_PATTERNS) && !haystack.match?(REMOTE_PATTERNS)

        !(remote_signal.to_s.match?(REMOTE_PATTERNS) || haystack.match?(REMOTE_PATTERNS))
      end

      def seniority?(text)
        text.match?(SENIORITY_PATTERNS)
      end

      def title_stack_tags(text)
        stack_tags(text)
      end

      def stack_tags(text)
        STACK_PATTERNS.each_with_object([]) do |(tag, pattern), result|
          result << tag if text.match?(pattern)
        end
      end

      def normalize(value)
        value.to_s.downcase.squish
      end
  end
end
