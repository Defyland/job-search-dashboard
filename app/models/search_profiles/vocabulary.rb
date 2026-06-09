module SearchProfiles
  module Vocabulary
    extend self

    BOOLEAN = ActiveModel::Type::Boolean.new

    DEFAULT_NAME = "Senior Ruby/Rails/React Remote BR/LatAm".freeze
    DEFAULT_LANGUAGE_SCOPE = "both".freeze
    DEFAULT_SENIORITY_PRESET = "senior".freeze
    DEFAULT_REGION_SCOPE = "brazil_latam".freeze
    DEFAULT_TARGET_STACKS = [ "ruby", "ruby on rails", "react", "react native" ].freeze
    DEFAULT_TARGET_TITLES = [ "software engineer", "engenheiro de software", "frontend", "backend", "fullstack", "developer", "desenvolvedor" ].freeze
    DEFAULT_SENIORITY_TERMS = [ "senior", "sênior", "sr", "staff" ].freeze
    DEFAULT_LOCATION_TERMS = [ "remoto", "remote", "home office", "brasil", "brazil", "latam" ].freeze
    DEFAULT_NEGATIVE_TERMS = [ "junior", "júnior", "pleno", "mid-level", "trainee", "intern", "internship", "estágio" ].freeze
    WOMEN_ONLY_EXCLUDE_TERMS = [ "mulheres", "women only", "female only" ].freeze
    LANGUAGE_SCOPE_ENUM = { both: 0, portuguese: 1, english: 2 }.freeze
    LANGUAGE_SCOPE_LABELS = {
      "both" => "Português e Inglês",
      "portuguese" => "Português",
      "english" => "Inglês"
    }.freeze
    SENIORITY_PRESETS = {
      "senior" => [ "senior", "sênior", "sr", "staff" ],
      "staff" => [ "staff", "senior staff", "sr staff" ],
      "principal" => [ "principal", "staff", "senior staff" ]
    }.freeze
    SENIORITY_PRESET_LABELS = {
      "senior" => "Senior",
      "staff" => "Staff",
      "principal" => "Principal"
    }.freeze
    REGION_TERMS = {
      "brazil_latam" => [ "brasil", "brazil", "latam" ],
      "brazil" => [ "brasil", "brazil" ],
      "latam" => [ "latam" ],
      "global_remote" => [ "worldwide", "global", "anywhere" ]
    }.freeze
    REGION_SCOPE_LABELS = {
      "brazil_latam" => "Brasil e LatAm",
      "brazil" => "Brasil",
      "latam" => "LatAm",
      "global_remote" => "Global remoto"
    }.freeze
    ROLE_TITLES_BY_LANGUAGE = {
      "both" => DEFAULT_TARGET_TITLES,
      "portuguese" => [ "engenheiro de software", "desenvolvedor", "frontend", "backend", "fullstack" ],
      "english" => [ "software engineer", "developer", "frontend", "backend", "fullstack" ]
    }.freeze
    MANUAL_OVERRIDE_FIELDS = {
      target_stacks: "target_stacks_text",
      target_titles: "target_titles_text",
      seniority_terms: "seniority_terms_text",
      location_terms: "location_terms_text",
      negative_terms: "negative_terms_text"
    }.freeze

    def default_attributes
      {
        name: DEFAULT_NAME,
        target_stacks: DEFAULT_TARGET_STACKS,
        target_titles: DEFAULT_TARGET_TITLES,
        seniority_terms: DEFAULT_SENIORITY_TERMS,
        location_terms: DEFAULT_LOCATION_TERMS,
        negative_terms: DEFAULT_NEGATIVE_TERMS,
        language_scope: DEFAULT_LANGUAGE_SCOPE,
        required_remote: true,
        include_women_only: false,
        scan_window_days: 20,
        active: true
      }
    end

    def normalize_list(values)
      Array(values).flat_map { |value| value.to_s.split(/[\n,;]/) }
                   .map { |value| normalize(value) }
                   .reject(&:blank?)
                   .uniq
    end

    def normalize(value)
      value.to_s.downcase.squish
    end

    def normalize_language_scope(value)
      value = value.to_s
      LANGUAGE_SCOPE_LABELS.key?(value) ? value : DEFAULT_LANGUAGE_SCOPE
    end

    def normalize_seniority_preset(value)
      value = value.to_s
      SENIORITY_PRESETS.key?(value) ? value : DEFAULT_SENIORITY_PRESET
    end

    def normalize_region_scope(value)
      value = value.to_s
      REGION_TERMS.key?(value) ? value : DEFAULT_REGION_SCOPE
    end

    def role_titles_for(language_scope)
      ROLE_TITLES_BY_LANGUAGE.fetch(normalize_language_scope(language_scope), ROLE_TITLES_BY_LANGUAGE.fetch(DEFAULT_LANGUAGE_SCOPE))
    end

    def location_terms_for(required_remote:, region_scope:)
      remote_terms = BOOLEAN.cast(required_remote) ? [ "remoto", "remote", "home office" ] : []
      normalize_list(remote_terms + REGION_TERMS.fetch(normalize_region_scope(region_scope)))
    end

    def infer_seniority_preset(terms)
      normalized_terms = normalize_list(terms)

      if normalized_terms.any? { |term| term.include?("principal") }
        "principal"
      elsif normalized_terms.any? { |term| term.include?("staff") } &&
          normalized_terms.none? { |term| term.include?("senior") || term.include?("sênior") }
        "staff"
      else
        DEFAULT_SENIORITY_PRESET
      end
    end

    def infer_region_scope(terms)
      normalized_terms = normalize_list(terms)
      has_brazil = normalized_terms.intersect?(%w[brasil brazil])
      has_latam = normalized_terms.include?("latam")
      has_global = normalized_terms.intersect?(%w[worldwide global anywhere])

      if has_brazil && has_latam
        "brazil_latam"
      elsif has_brazil
        "brazil"
      elsif has_latam
        "latam"
      elsif has_global
        "global_remote"
      else
        DEFAULT_REGION_SCOPE
      end
    end

    def language_scope_label(value)
      LANGUAGE_SCOPE_LABELS.fetch(normalize_language_scope(value), LANGUAGE_SCOPE_LABELS.fetch(DEFAULT_LANGUAGE_SCOPE))
    end

    def effective_exclude_terms(negative_terms:, include_women_only:)
      terms = normalize_list(negative_terms)
      terms + (BOOLEAN.cast(include_women_only) ? [] : WOMEN_ONLY_EXCLUDE_TERMS)
    end
  end
end
