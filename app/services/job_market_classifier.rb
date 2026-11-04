class JobMarketClassifier
  UNKNOWN = "unknown".freeze
  NATIONAL = "national".freeze
  INTERNATIONAL = "international".freeze

  PLACEHOLDER_PHRASES = [ "sem data publica" ].freeze

  BRAZIL_PHRASES = [
    "brasil",
    "brazil",
    "sao paulo",
    "rio de janeiro",
    "belo horizonte",
    "curitiba",
    "porto alegre",
    "florianopolis",
    "recife",
    "brasilia",
    "campinas"
  ].freeze

  RESTRICTED_BRAZIL_PHRASES = [
    "anywhere in brazil",
    "todo o brasil",
    "qualquer lugar do brasil"
  ].freeze

  GLOBAL_PHRASES = [
    "worldwide",
    "global",
    "anywhere",
    "work from anywhere",
    "qualquer lugar",
    "international"
  ].freeze

  REGION_PHRASES = [
    "latam",
    "latin america",
    "america latina",
    "south america",
    "americas",
    "north america",
    "emea",
    "europe",
    "apac"
  ].freeze

  FOREIGN_PHRASES = [
    "portugal",
    "united states",
    "usa",
    "canada",
    "mexico",
    "argentina",
    "chile",
    "colombia",
    "uruguay",
    "peru",
    "spain",
    "germany",
    "united kingdom",
    "ireland",
    "netherlands",
    "france",
    "india"
  ].freeze

  # Only the location and remote texts are inputs. Title, company, language,
  # description, raw payload, ATS and currency must never reach this classifier.
  def self.call(...)
    new(...).call
  end

  def initialize(location_text:, remote_text:)
    @text = normalize([ location_text, remote_text ].join(" "))
  end

  # Precedence is first match wins. Restricted Brazil overrides global words,
  # and a Brazil + foreign-country mix is international.
  def call
    return UNKNOWN if @text.empty?
    return NATIONAL if matches_any?(RESTRICTED_BRAZIL_PHRASES)
    return INTERNATIONAL if matches_any?(GLOBAL_PHRASES) || matches_any?(REGION_PHRASES)

    brazil = matches_any?(BRAZIL_PHRASES)
    foreign = matches_any?(FOREIGN_PHRASES)

    return INTERNATIONAL if brazil && foreign
    return NATIONAL if brazil
    return INTERNATIONAL if foreign

    UNKNOWN
  end

  private
    def normalize(value)
      text = I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
      PLACEHOLDER_PHRASES.reduce(text) { |current, phrase| current.gsub(/\b#{phrase}\b/, " ") }.squish
    end

    # Whole-word match: the text is padded so each phrase must be surrounded by spaces.
    def matches_any?(phrases)
      padded = " #{@text} "
      phrases.any? { |phrase| padded.include?(" #{phrase} ") }
    end
end
