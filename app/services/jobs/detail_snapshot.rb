require "cgi"

module Jobs
  class DetailSnapshot
    DESCRIPTION_KEYS = %w[
      description
      descriptionPlain
      descriptionBodyPlain
      description_html
      job_description
      content
      body
      summary
      openingPlain
      additionalPlain
    ].freeze

    SECTION_HEADERS = {
      responsibilities: /\A(responsabilidades|atividades|o que voce vai fazer|o que você vai fazer|what you'?ll do|responsibilities)\b/i,
      requirements: /\A(requisitos|qualificacoes|qualificações|required|requirements|must have|o que esperamos|skills)\b/i,
      benefits: /\A(beneficios|benefícios|benefits|perks|o que oferecemos|oferecemos)\b/i
    }.freeze

    KEYWORD_PATTERNS = {
      responsibilities: /\b(desenvolver|atuar|construir|manter|colaborar|build|develop|maintain|work with|deliver)\b/i,
      requirements: /\b(experiencia|experiência|conhecimento|requisito|required|experience|must|proficient|conhecimento em)\b/i,
      benefits: /\b(beneficio|benefício|vale|plano de saude|plano de saúde|gympass|bonus|bônus|benefit|health|remote)\b/i
    }.freeze

    def initialize(job:, job_match:, search_profile:)
      @job = job
      @job_match = job_match
      @search_profile = search_profile
    end

    def description_text
      @description_text ||= extract_description.presence || fallback_description
    end

    def description_available?
      extract_description.present?
    end

    def responsibilities
      section_items(:responsibilities)
    end

    def requirements
      section_items(:requirements)
    end

    def benefits
      section_items(:benefits)
    end

    def attention_points
      [
        ("Vaga expirada no radar." if @job.lifecycle_state_expired?),
        ("Match borderline: revise os requisitos antes de aplicar." if @job_match.match_strength_borderline?),
        ("Descricao completa nao foi capturada; use o link original para confirmar requisitos." unless description_available?),
        ("Perfil exige remoto, mas a vaga tem sinal de hibrido/presencial." if remote_conflict?)
      ].compact
    end

    def source_snapshot_label
      timestamp = @job.last_validated_at || @job.last_seen_at || @job.updated_at
      "Snapshot capturado em #{I18n.l(timestamp, format: :short)}"
    end

    private
      def extract_description
        return @extracted_description if defined?(@extracted_description)

        payload = @job.raw_payload.to_h.deep_stringify_keys
        candidates = DESCRIPTION_KEYS.filter_map { |key| text_from(payload[key]) }
        candidates << text_from(payload.dig("source_payload", "description"))
        candidates << text_from(payload.dig("payload", "description"))
        @extracted_description = candidates.compact_blank.max_by(&:length).to_s
      end

      def fallback_description
        [
          @job.title,
          @job.company_name,
          @job.remote_text,
          @job.location_text,
          @job.posted_text,
          @job_match.reason
        ].compact_blank.join("\n")
      end

      def section_items(section)
        explicit_sections.fetch(section) do
          lines_matching(KEYWORD_PATTERNS.fetch(section))
        end.first(6)
      end

      def explicit_sections
        @explicit_sections ||= begin
          sections = Hash.new { |hash, key| hash[key] = [] }
          current_section = nil

          description_lines.each do |line|
            header_section, remainder = header_match(line)
            if header_section
              current_section = header_section
              sections[current_section] << remainder if remainder.present?
              next
            end

            sections[current_section] << line if current_section
          end

          sections.transform_values { |items| normalize_items(items) }
        end
      end

      def header_match(line)
        SECTION_HEADERS.each do |section, pattern|
          next unless line.match?(pattern)

          remainder = line.sub(pattern, "").sub(/\A\s*[:\-–]\s*/, "")
          return [ section, remainder ]
        end

        nil
      end

      def lines_matching(pattern)
        normalize_items(description_lines.select { |line| line.match?(pattern) })
      end

      def description_lines
        @description_lines ||= description_text.split(/\n+/).map(&:squish).reject(&:blank?)
      end

      def normalize_items(items)
        items.map { |item| item.to_s.squish }
             .reject(&:blank?)
             .uniq
      end

      def remote_conflict?
        return false unless @search_profile.required_remote?

        [ @job.remote_text, @job.location_text, description_text ].join(" ").match?(/\b(hibrid|hybrid|presencial|onsite|on-site)\b/i)
      end

      def text_from(value)
        case value
        when String
          normalize_text(value)
        when Array
          normalize_text(value.filter_map { |entry| text_from(entry) }.join("\n"))
        when Hash
          nested = DESCRIPTION_KEYS.filter_map { |key| text_from(value[key]) }
          normalize_text(nested.join("\n"))
        end
      end

      def normalize_text(value)
        text = value.to_s
        text = text.gsub(/<(script|style)\b[^>]*>.*?<\/\1>/im, "")
        text = text.gsub(/<(br|\/p|\/li|\/h[1-6])\b[^>]*>/i, "\n")
        text = ActionView::Base.full_sanitizer.sanitize(text)
        text = CGI.unescapeHTML(text)
        text.gsub(/\r\n?/, "\n")
            .gsub(/[ \t]+/, " ")
            .gsub(/\n[ \t]+/, "\n")
            .gsub(/\n{3,}/, "\n\n")
            .strip
      end
  end
end
