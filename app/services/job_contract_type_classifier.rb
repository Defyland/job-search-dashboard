class JobContractTypeClassifier
  HIGH_SIGNAL_KEY_PATTERN = /
    employment|employmenttype|employment_type|
    contract|contracttype|contract_type|
    regime|hiring|hire|jobtype|job_type|
    type_formatted|modalidade|modelo
  /ix

  BOTH_PATTERNS = [
    /\bclt\s*(?:ou|e|\/)\s*pj\b/,
    /\bpj\s*(?:ou|e|\/)\s*clt\b/,
    /\bcontractor\s*(?:or|and|\/)\s*(?:employee|employer)\b/,
    /\b(?:employee|employer)\s*(?:or|and|\/)\s*contractor\b/
  ].freeze

  HIGH_SIGNAL_PJ_PATTERNS = [
    /\bpj\b/,
    /\bpessoa juridica\b/,
    /\bcontractor\b/,
    /\bcontract\b/,
    /\bfreelance\b/
  ].freeze

  HIGH_SIGNAL_CLT_PATTERNS = [
    /\bclt\b/,
    /\bemployee\b/,
    /\bemployer\b/,
    /\bpermanent\b/,
    /\befetivo\b/
  ].freeze

  BODY_PJ_PATTERNS = [
    /\bcontratacao\s+pj\b/,
    /\bcontrato\s+pj\b/,
    /\bregime\s+pj\b/,
    /\bmodelo\s+pj\b/,
    /\bcomo\s+pj\b/,
    /\bpessoa juridica\b/,
    /\bprestacao\s+de\s+servicos\b/
  ].freeze

  BODY_CLT_PATTERNS = [
    /\bcontratacao\s+clt\b/,
    /\bcontrato\s+clt\b/,
    /\bregime\s+clt\b/,
    /\bmodelo\s+clt\b/,
    /\befetivo\s+clt\b/
  ].freeze

  def self.call(...)
    new(...).call
  end

  def initialize(title: nil, remote_text: nil, location_text: nil, posted_text: nil, raw_payload: {})
    @title = title
    @remote_text = remote_text
    @location_text = location_text
    @posted_text = posted_text
    @raw_payload = raw_payload.to_h.deep_stringify_keys
  end

  def call
    high_signal_text = normalize(extract_high_signal_text(@raw_payload).join(" "))
    body_text = normalize([ @title, @remote_text, @location_text, @posted_text, description_text ].join(" "))

    return "clt_or_pj" if both_contract_types?(high_signal_text) || both_contract_types?(body_text)

    pj_signal = matches_any?(high_signal_text, HIGH_SIGNAL_PJ_PATTERNS) || matches_any?(body_text, BODY_PJ_PATTERNS)
    clt_signal = matches_any?(high_signal_text, HIGH_SIGNAL_CLT_PATTERNS) || matches_any?(body_text, BODY_CLT_PATTERNS)

    return "clt_or_pj" if pj_signal && clt_signal
    return "pj" if pj_signal
    return "clt" if clt_signal

    "unknown"
  end

  private
    def extract_high_signal_text(value, parent_key: nil)
      result =
        case value
        when Hash
          value.flat_map do |key, child|
            key_text = key.to_s
            if high_signal_key?(key_text)
              [ key_text, extract_all_text(child) ].flatten
            else
              extract_high_signal_text(child, parent_key: key_text)
            end
          end
        when Array
          value.flat_map { |child| extract_high_signal_text(child, parent_key:) }
        else
          high_signal_key?(parent_key.to_s) ? value.to_s : nil
        end

      Array(result).flatten.compact_blank
    end

    def extract_all_text(value)
      case value
      when Hash
        value.flat_map { |key, child| [ key.to_s, extract_all_text(child) ] }
      when Array
        value.flat_map { |child| extract_all_text(child) }
      else
        value.to_s
      end
    end

    def description_text
      [
        @raw_payload["description"],
        @raw_payload["body"],
        @raw_payload["summary"],
        @raw_payload.dig("source_payload", "description")
      ].compact.join(" ")
    end

    def both_contract_types?(text)
      matches_any?(text, BOTH_PATTERNS)
    end

    def matches_any?(text, patterns)
      patterns.any? { |pattern| text.match?(pattern) }
    end

    def high_signal_key?(key)
      key.match?(HIGH_SIGNAL_KEY_PATTERN)
    end

    def normalize(text)
      I18n.transliterate(text.to_s.downcase).squish
    end
end
