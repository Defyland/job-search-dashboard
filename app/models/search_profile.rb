class SearchProfile < ApplicationRecord
  DEFAULT_TARGET_STACKS = [ "ruby", "ruby on rails", "react", "react native" ].freeze
  DEFAULT_TARGET_TITLES = [ "software engineer", "engenheiro de software", "frontend", "backend", "fullstack", "developer", "desenvolvedor" ].freeze
  DEFAULT_SENIORITY_TERMS = [ "senior", "sênior", "sr", "staff" ].freeze
  DEFAULT_LOCATION_TERMS = [ "remoto", "remote", "home office", "brasil", "brazil", "latam" ].freeze
  DEFAULT_NEGATIVE_TERMS = [ "junior", "júnior", "pleno", "mid-level", "trainee", "intern", "internship", "estágio" ].freeze

  belongs_to :user

  has_many :job_matches, dependent: :destroy
  has_many :jobs, through: :job_matches

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
      required_remote: true,
      include_women_only: false,
      scan_window_days: 20,
      active: true
    }
  end

  def policy_contract
    {
      profile_id: id,
      profile_name: name,
      seniority_terms: seniority_terms,
      stack_terms: target_stacks,
      title_terms: target_titles,
      location_terms: location_terms,
      required_remote: required_remote?,
      include_women_only: include_women_only?,
      exclude_terms: effective_exclude_terms,
      output: "POST accepted strong/borderline jobs and useful rejections to /api/v1/job_ingestions"
    }
  end

  def effective_exclude_terms
    terms = negative_terms.dup
    terms += [ "mulheres", "women only", "female only" ] unless include_women_only?
    terms
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
    def apply_defaults
      self.name = name.presence || self.class.default_attributes.fetch(:name)
      self.slug = slug.presence || name
      self.slug = slug.to_s.parameterize
      self.target_stacks = normalize_list(target_stacks.presence || DEFAULT_TARGET_STACKS)
      self.target_titles = normalize_list(target_titles.presence || DEFAULT_TARGET_TITLES)
      self.seniority_terms = normalize_list(seniority_terms.presence || DEFAULT_SENIORITY_TERMS)
      self.location_terms = normalize_list(location_terms.presence || DEFAULT_LOCATION_TERMS)
      self.negative_terms = normalize_list(negative_terms.presence || DEFAULT_NEGATIVE_TERMS)
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
