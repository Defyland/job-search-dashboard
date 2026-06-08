class JobTitleLanguage
  FILTER_OPTIONS = [
    [ "Todos", "all" ],
    [ "Português", "portuguese" ],
    [ "Inglês", "english" ]
  ].freeze

  PORTUGUESE_MARKERS = [
    "engenheiro",
    "engenheira",
    "desenvolvedor",
    "desenvolvedora",
    "analista",
    "arquiteto",
    "arquiteta",
    "consultor",
    "consultora",
    "profissional",
    "desenvolvimento",
    "sênior"
  ].freeze

  ENGLISH_MARKERS = [
    "software engineer",
    "engineer",
    "developer",
    "architect",
    "consultant"
  ].freeze

  class << self
    def detect(title)
      text = normalize(title)
      return "unknown" if text.blank?

      portuguese = matches_any?(text, PORTUGUESE_MARKERS)
      english = matches_any?(text, ENGLISH_MARKERS)

      return "both" if portuguese && english
      return "portuguese" if portuguese
      return "english" if english

      "unknown"
    end

    def filter_scope(scope, language)
      case language.to_s
      when "portuguese"
        apply_marker_filter(scope, PORTUGUESE_MARKERS)
      when "english"
        apply_marker_filter(scope, ENGLISH_MARKERS)
      else
        scope
      end
    end

    private
      def apply_marker_filter(scope, markers)
        clauses = markers.map { "jobs.title ILIKE ?" }.join(" OR ")
        values = markers.map { |marker| "%#{marker}%" }
        scope.where(clauses, *values)
      end

      def matches_any?(text, markers)
        markers.any? { |marker| text.include?(normalize(marker)) }
      end

      def normalize(value)
        value.to_s.downcase.squish
      end
  end
end
