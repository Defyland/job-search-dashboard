class SearchProfile < ApplicationRecord
  DEFAULT_TARGET_STACKS = SearchProfiles::Vocabulary::DEFAULT_TARGET_STACKS
  DEFAULT_TARGET_TITLES = SearchProfiles::Vocabulary::DEFAULT_TARGET_TITLES
  DEFAULT_SENIORITY_TERMS = SearchProfiles::Vocabulary::DEFAULT_SENIORITY_TERMS
  DEFAULT_LOCATION_TERMS = SearchProfiles::Vocabulary::DEFAULT_LOCATION_TERMS
  DEFAULT_NEGATIVE_TERMS = SearchProfiles::Vocabulary::DEFAULT_NEGATIVE_TERMS
  MAX_SCAN_WINDOW_DAYS = SearchProfiles::Vocabulary::MAX_SCAN_WINDOW_DAYS
  SENIORITY_PRESET_LABELS = SearchProfiles::Vocabulary::SENIORITY_PRESET_LABELS
  REGION_SCOPE_LABELS = SearchProfiles::Vocabulary::REGION_SCOPE_LABELS
  LANGUAGE_SCOPE_LABELS = SearchProfiles::Vocabulary::LANGUAGE_SCOPE_LABELS

  belongs_to :user

  has_many :job_matches, dependent: :destroy
  has_many :jobs, through: :job_matches

  enum :language_scope, SearchProfiles::Vocabulary::LANGUAGE_SCOPE_ENUM, prefix: true, validate: true
  enum :sync_state, { idle: 0, pending: 1, syncing: 2, synced: 3, failed: 4 }, prefix: true, validate: true

  normalizes :name, with: ->(value) { value.to_s.squish }

  validates :name, :slug, presence: true
  validates :slug, uniqueness: { scope: :user_id }
  validates :scan_window_days, numericality: { greater_than: 0, less_than_or_equal_to: MAX_SCAN_WINDOW_DAYS }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(active: :desc, name: :asc) }

  before_validation :apply_defaults

  def self.ensure_default_for(user)
    user.search_profiles.ordered.first || user.search_profiles.create!(default_attributes)
  end

  def self.default_attributes
    SearchProfiles::Vocabulary.default_attributes
  end

  def policy_contract
    JobDiscovery::PolicyContractSerializer.dump(self)
  end

  def effective_exclude_terms
    SearchProfiles::Vocabulary.effective_exclude_terms(
      negative_terms:,
      include_women_only:
    )
  end

  def language_scope_label
    SearchProfiles::Vocabulary.language_scope_label(language_scope)
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
      normalized_aliases = SearchProfiles::Vocabulary.normalize_list(aliases)
      next if normalized_stack.blank? || normalized_aliases.blank?

      result[normalized_stack] = normalized_aliases
    end
  end

  def simple_form_state
    {
      "name" => name,
      "technology_intent" => intent_settings["technology_intent"].presence || target_stacks_text,
      "seniority_preset" => intent_settings["seniority_preset"].presence || SearchProfiles::Vocabulary.infer_seniority_preset(seniority_terms),
      "language_scope" => language_scope.to_s.presence || SearchProfiles::Vocabulary::DEFAULT_LANGUAGE_SCOPE,
      "required_remote" => required_remote.nil? ? true : required_remote,
      "region_scope" => intent_settings["region_scope"].presence || SearchProfiles::Vocabulary.infer_region_scope(location_terms),
      "include_women_only" => include_women_only.nil? ? false : include_women_only,
      "scan_window_days" => SearchProfiles::Vocabulary.normalize_scan_window_days(scan_window_days)
    }
  end

  def sync_status_label
    case sync_state
    when "pending"
      "Enfileirada"
    when "syncing"
      "Sincronizando"
    when "synced"
      "Cache atualizado"
    when "failed"
      "Falhou"
    else
      "Sem sync"
    end
  end

  def sync_status_tone
    case sync_state
    when "pending", "syncing"
      :borderline
    when "synced"
      :active
    when "failed"
      :expired
    else
      :ignored
    end
  end

  def sync_status_detail
    return last_sync_error if sync_state_failed? && last_sync_error.present?
    return "Cache local atualizado; busca externa enfileirada." if sync_state_synced?
    return "Solicitado em #{I18n.l(last_sync_requested_at, format: :short)}." if sync_state_pending? && last_sync_requested_at.present?
    return "Ultimo cache em #{I18n.l(last_synced_at, format: :short)}." if last_synced_at.present?

    "Nenhuma sincronizacao recente."
  end

  %i[target_stacks target_titles seniority_terms location_terms negative_terms].each do |field|
    define_method("#{field}_text") do
      public_send(field).join(", ")
    end

    define_method("#{field}_text=") do |value|
      public_send("#{field}=", SearchProfiles::Vocabulary.normalize_list(value))
    end
  end

  private
    def apply_defaults
      self.name = name.presence || self.class.default_attributes.fetch(:name)
      self.slug = slug.presence || name
      self.slug = slug.to_s.parameterize
      self.target_stacks = SearchProfiles::Vocabulary.normalize_list(target_stacks.presence || DEFAULT_TARGET_STACKS)
      self.target_titles = SearchProfiles::Vocabulary.normalize_list(target_titles.presence || DEFAULT_TARGET_TITLES)
      self.seniority_terms = SearchProfiles::Vocabulary.normalize_list(seniority_terms.presence || DEFAULT_SENIORITY_TERMS)
      self.location_terms = SearchProfiles::Vocabulary.normalize_list(location_terms.presence || DEFAULT_LOCATION_TERMS)
      self.negative_terms = SearchProfiles::Vocabulary.normalize_list(negative_terms.presence || DEFAULT_NEGATIVE_TERMS)
      self.language_scope = language_scope.presence || SearchProfiles::Vocabulary::DEFAULT_LANGUAGE_SCOPE
      self.scan_window_days ||= SearchProfiles::Vocabulary::DEFAULT_SCAN_WINDOW_DAYS
      self.settings ||= {}
      self.active = true if active.nil?
      self.required_remote = true if required_remote.nil?
      self.include_women_only = false if include_women_only.nil?
      self.sync_state ||= :idle
    end
end
