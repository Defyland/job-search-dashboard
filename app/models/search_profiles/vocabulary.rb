module SearchProfiles
  module Vocabulary
    extend self

    BOOLEAN = ActiveModel::Type::Boolean.new

    DEFAULT_NAME = "Senior Ruby/Rails/React Remote BR/LatAm".freeze
    DEFAULT_LANGUAGE_SCOPE = "both".freeze
    DEFAULT_SENIORITY_PRESET = "senior".freeze
    DEFAULT_REGION_SCOPE = "brazil_latam".freeze
    DEFAULT_SCAN_WINDOW_DAYS = 20
    MAX_SCAN_WINDOW_DAYS = 60
    SCAN_WINDOW_DAY_OPTIONS = [
      [ "24h", 1 ],
      [ "7 dias", 7 ],
      [ "14 dias", 14 ],
      [ "20 dias", 20 ],
      [ "30 dias", 30 ],
      [ "45 dias", 45 ],
      [ "60 dias", 60 ]
    ].freeze
    SCAN_WINDOW_DAY_LABELS = SCAN_WINDOW_DAY_OPTIONS.to_h { |label, days| [ days, label ] }.freeze
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
      "junior" => [ "junior", "júnior", "jr", "entry level" ],
      "mid" => [ "pleno", "mid-level", "mid level", "mid", "intermediate" ],
      "senior" => [ "senior", "sênior", "sr", "staff" ],
      "staff" => [ "staff", "senior staff", "sr staff" ],
      "principal" => [ "principal", "staff", "senior staff" ]
    }.freeze
    SENIORITY_PRESET_LABELS = {
      "junior" => "Junior",
      "mid" => "Pleno",
      "senior" => "Senior",
      "staff" => "Staff",
      "principal" => "Principal"
    }.freeze
    NEGATIVE_TERMS_BY_SENIORITY = {
      "junior" => [
        "senior", "sênior", "sr", "staff", "principal", "pleno",
        "mid-level", "mid level", "trainee", "intern", "internship", "estágio"
      ],
      "mid" => [
        "junior", "júnior", "jr", "senior", "sênior", "sr",
        "staff", "principal", "trainee", "intern", "internship", "estágio"
      ],
      "senior" => DEFAULT_NEGATIVE_TERMS,
      "staff" => DEFAULT_NEGATIVE_TERMS,
      "principal" => DEFAULT_NEGATIVE_TERMS
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
    NON_TECH_ROLE_STACKS = %w[recruiter rh].freeze
    NON_TECH_ROLE_TITLES = {
      "recruiter" => {
        "portuguese" => [
          "recruiter",
          "recrutador",
          "recrutadora",
          "analista de recrutamento",
          "analista de recrutamento e selecao",
          "analista de recrutamento e seleção",
          "talent acquisition"
        ],
        "english" => [
          "recruiter",
          "tech recruiter",
          "technical recruiter",
          "talent acquisition",
          "talent acquisition specialist",
          "talent acquisition partner"
        ]
      },
      "rh" => {
        "portuguese" => [
          "rh",
          "analista de rh",
          "analista de recursos humanos",
          "business partner de rh",
          "coordenador de rh",
          "people partner"
        ],
        "english" => [
          "human resources",
          "human resources specialist",
          "hr business partner",
          "people operations",
          "people ops",
          "people partner"
        ]
      }
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
        scan_window_days: DEFAULT_SCAN_WINDOW_DAYS,
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

    def normalize_scan_window_days(value)
      (value.presence || DEFAULT_SCAN_WINDOW_DAYS).to_i.clamp(1, MAX_SCAN_WINDOW_DAYS)
    end

    def scan_window_label(value)
      normalized_value = normalize_scan_window_days(value)
      SCAN_WINDOW_DAY_LABELS.fetch(normalized_value, "#{normalized_value} dias")
    end

    def role_titles_for(language_scope, target_stacks: [])
      non_tech_titles = non_tech_role_titles_for(target_stacks, language_scope)
      return non_tech_titles if non_tech_titles.present?

      ROLE_TITLES_BY_LANGUAGE.fetch(normalize_language_scope(language_scope), ROLE_TITLES_BY_LANGUAGE.fetch(DEFAULT_LANGUAGE_SCOPE))
    end

    def non_tech_role_stack?(target_stacks)
      normalize_list(target_stacks).intersect?(NON_TECH_ROLE_STACKS)
    end

    def non_tech_role_titles_for(target_stacks, language_scope)
      normalized_language_scope = normalize_language_scope(language_scope)

      normalize_list(target_stacks).flat_map do |stack|
        titles = NON_TECH_ROLE_TITLES[stack]
        next [] unless titles

        case normalized_language_scope
        when "portuguese"
          titles.fetch("portuguese")
        when "english"
          titles.fetch("english")
        else
          titles.fetch("portuguese") + titles.fetch("english")
        end
      end.then { |titles| normalize_list(titles) }
    end

    def location_terms_for(required_remote:, region_scope:)
      remote_terms = BOOLEAN.cast(required_remote) ? [ "remoto", "remote", "home office" ] : []
      normalize_list(remote_terms + REGION_TERMS.fetch(normalize_region_scope(region_scope)))
    end

    def negative_terms_for(seniority_preset)
      NEGATIVE_TERMS_BY_SENIORITY.fetch(
        normalize_seniority_preset(seniority_preset),
        DEFAULT_NEGATIVE_TERMS
      )
    end

    def infer_seniority_preset(terms)
      normalized_terms = normalize_list(terms)

      if normalized_terms.any? { |term| term.include?("principal") }
        "principal"
      elsif normalized_terms.any? { |term| term.include?("staff") } &&
          normalized_terms.none? { |term| term.include?("senior") || term.include?("sênior") || term == "sr" }
        "staff"
      elsif normalized_terms.any? { |term| term.include?("senior") || term.include?("sênior") || term == "sr" }
        "senior"
      elsif normalized_terms.any? { |term| term.include?("pleno") || term.include?("mid") || term.include?("intermediate") }
        "mid"
      elsif normalized_terms.any? { |term| term.include?("junior") || term.include?("júnior") || term == "jr" || term.include?("entry level") }
        "junior"
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
