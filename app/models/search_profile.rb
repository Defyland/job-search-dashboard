class SearchProfile < ApplicationRecord
  DEFAULT_TARGET_STACKS = [ "ruby", "ruby on rails", "react", "react native" ].freeze
  DEFAULT_TARGET_TITLES = [ "software engineer", "engenheiro de software", "frontend", "backend", "fullstack", "developer", "desenvolvedor" ].freeze
  DEFAULT_SENIORITY_TERMS = [ "senior", "sênior", "sr", "staff" ].freeze
  DEFAULT_LOCATION_TERMS = [ "remoto", "remote", "home office", "brasil", "brazil", "latam" ].freeze
  DEFAULT_NEGATIVE_TERMS = [ "junior", "júnior", "pleno", "mid-level", "trainee", "intern", "internship", "estágio" ].freeze
  SENIORITY_PRESET_LABELS = {
    "senior" => "Senior",
    "staff" => "Staff",
    "principal" => "Principal"
  }.freeze
  REGION_SCOPE_LABELS = {
    "brazil_latam" => "Brasil e LatAm",
    "brazil" => "Brasil",
    "latam" => "LatAm",
    "global_remote" => "Global remoto"
  }.freeze
  LANGUAGE_SCOPE_LABELS = {
    "both" => "Português e Inglês",
    "portuguese" => "Português",
    "english" => "Inglês"
  }.freeze

  belongs_to :user

  has_many :job_matches, dependent: :destroy
  has_many :jobs, through: :job_matches

  enum :language_scope, { both: 0, portuguese: 1, english: 2 }, prefix: true, validate: true

  normalizes :name, with: ->(value) { value.to_s.squish }

  validates :name, :slug, presence: true
  validates :slug, uniqueness: { scope: :user_id }
  validates :scan_window_days, numericality: { greater_than: 0, less_than_or_equal_to: 60 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(active: :desc, name: :asc) }

  before_validation :apply_defaults

  def self.ensure_default_for(user)
    user.search_profiles.ordered.first || user.search_profiles.create!(default_attributes)
  end

  def self.default_attributes
    {
      name: "Senior Ruby/Rails/React Remote BR/LatAm",
      target_stacks: DEFAULT_TARGET_STACKS,
      target_titles: DEFAULT_TARGET_TITLES,
      seniority_terms: DEFAULT_SENIORITY_TERMS,
      location_terms: DEFAULT_LOCATION_TERMS,
      negative_terms: DEFAULT_NEGATIVE_TERMS,
      language_scope: :both,
      required_remote: true,
      include_women_only: false,
      scan_window_days: 20,
      active: true
    }
  end

  def policy_contract
    JobDiscovery::PolicyContractSerializer.dump(self)
  end

  def effective_exclude_terms
    terms = negative_terms.dup
    terms += [ "mulheres", "women only", "female only" ] unless include_women_only?
    terms
  end

  def language_scope_label
    LANGUAGE_SCOPE_LABELS.fetch(language_scope, LANGUAGE_SCOPE_LABELS.fetch("both"))
  end

  def intent_settings
    (settings || {}).fetch("intent", {})
  end

  def compiler_settings
    (settings || {}).fetch("compiler", {})
  end

  def intent_backed?
    intent_settings.present? && compiler_settings.present?
  end

  def compiler_stack_aliases
    raw_aliases = compiler_settings["stack_aliases"]
    return {} unless raw_aliases.is_a?(Hash)

    raw_aliases.each_with_object({}) do |(stack, aliases), result|
      normalized_stack = stack.to_s.downcase.squish
      normalized_aliases = normalize_list(aliases)
      next if normalized_stack.blank? || normalized_aliases.blank?

      result[normalized_stack] = normalized_aliases
    end
  end

  def simple_form_state
    {
      "name" => name,
      "technology_intent" => intent_settings["technology_intent"].presence || target_stacks_text,
      "seniority_preset" => intent_settings["seniority_preset"].presence || inferred_seniority_preset,
      "language_scope" => language_scope.to_s.presence || "both",
      "required_remote" => required_remote.nil? ? true : required_remote,
      "region_scope" => intent_settings["region_scope"].presence || inferred_region_scope,
      "include_women_only" => include_women_only.nil? ? false : include_women_only
    }
  end

  %i[target_stacks target_titles seniority_terms location_terms negative_terms].each do |field|
    define_method("#{field}_text") do
      public_send(field).join(", ")
    end

    define_method("#{field}_text=") do |value|
      public_send("#{field}=", normalize_list(value))
    end
  end

  private
    def inferred_seniority_preset
      terms = normalize_list(seniority_terms)

      if terms.any? { |term| term.include?("principal") }
        "principal"
      elsif terms.any? { |term| term.include?("staff") } && terms.none? { |term| term.include?("senior") || term.include?("sênior") }
        "staff"
      else
        "senior"
      end
    end

    def inferred_region_scope
      terms = normalize_list(location_terms)
      has_brazil = terms.intersect?(%w[brasil brazil])
      has_latam = terms.include?("latam")
      has_global = terms.intersect?(%w[worldwide global anywhere])

      if has_brazil && has_latam
        "brazil_latam"
      elsif has_brazil
        "brazil"
      elsif has_latam
        "latam"
      elsif has_global
        "global_remote"
      else
        "brazil_latam"
      end
    end

    def apply_defaults
      self.name = name.presence || self.class.default_attributes.fetch(:name)
      self.slug = slug.presence || name
      self.slug = slug.to_s.parameterize
      self.target_stacks = normalize_list(target_stacks.presence || DEFAULT_TARGET_STACKS)
      self.target_titles = normalize_list(target_titles.presence || DEFAULT_TARGET_TITLES)
      self.seniority_terms = normalize_list(seniority_terms.presence || DEFAULT_SENIORITY_TERMS)
      self.location_terms = normalize_list(location_terms.presence || DEFAULT_LOCATION_TERMS)
      self.negative_terms = normalize_list(negative_terms.presence || DEFAULT_NEGATIVE_TERMS)
      self.language_scope = language_scope.presence || "both"
      self.scan_window_days ||= 20
      self.settings ||= {}
      self.active = true if active.nil?
      self.required_remote = true if required_remote.nil?
      self.include_women_only = false if include_women_only.nil?
    end

    def normalize_list(values)
      Array(values).flat_map { |value| value.to_s.split(",") }
                   .map { |value| value.downcase.squish }
                   .reject(&:blank?)
                   .uniq
    end
end
