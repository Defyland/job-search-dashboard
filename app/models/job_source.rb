class JobSource < ApplicationRecord
  enum :source_kind, { ats: 0, platform: 1, company: 2, aggregator: 3 }, prefix: true

  has_many :jobs, dependent: :restrict_with_exception
  has_many :source_scans, dependent: :restrict_with_exception
  has_many :discovered_jobs, dependent: :restrict_with_exception

  validates :name, :slug, :host, presence: true
  validates :slug, uniqueness: true
  validates :priority, numericality: { greater_than_or_equal_to: 0 }
  validates :scan_window_days, numericality: { greater_than: 0 }
  validate :validate_backfill_adapter_support

  scope :enabled, -> { where(enabled: true) }
  scope :backfillable, -> { enabled.where(supports_backfill: true) }
  scope :codex_fallback, -> { enabled.where(codex_fallback_enabled: true) }

  before_validation :normalize_fields

  private
    def normalize_fields
      self.name = name.to_s.strip
      self.base_url = normalize_url(base_url)
      self.host = normalized_host.presence
      self.slug = slug.presence || name.presence || host
      self.slug = slug.to_s.parameterize
      self.priority ||= 100
      self.adapter_key = adapter_key.presence || "manual_only"
      self.enabled = true if enabled.nil?
      self.supports_backfill = false if supports_backfill.nil?
      self.codex_fallback_enabled = false if codex_fallback_enabled.nil?
      self.codex_fallback_reason = codex_fallback_reason.to_s.squish.presence
      self.scan_window_days ||= 20
      self.settings ||= {}
    end

    def normalized_host
      raw_host = host.presence || extract_host(base_url)
      raw_host.to_s.downcase.sub(/\Awww\./, "")
    end

    def extract_host(url)
      URI.parse(url).host
    rescue URI::InvalidURIError, NoMethodError
      nil
    end

    def normalize_url(url)
      return if url.blank?

      url.to_s.strip.delete_suffix("/")
    end

    def validate_backfill_adapter_support
      return unless supports_backfill?
      return if JobSources::Catalog.supported_backfill_adapter?(adapter_key)

      errors.add(:adapter_key, "nao suporta backfill nativo")
    end
end
