class Job < ApplicationRecord
  belongs_to :job_source

  has_many :search_run_items, dependent: :nullify
  has_many :discovered_jobs, dependent: :nullify
  has_many :job_matches, dependent: :destroy
  has_many :search_profiles, through: :job_matches

  enum :lifecycle_state, { active: 0, expired: 1 }, prefix: true
  enum :contract_type, { unknown: 0, clt: 1, pj: 2, clt_or_pj: 3 }, prefix: true

  normalizes :title, with: ->(value) { value.to_s.squish }
  normalizes :company_name, with: ->(value) { value.to_s.squish }
  normalizes :apply_url, with: ->(value) { value.to_s.strip }
  normalizes :canonical_url, with: ->(value) { value.to_s.strip }
  normalizes :source_url, with: ->(value) { value.to_s.strip }

  validates :title, :company_name, :apply_url, :canonical_url, :fingerprint, presence: true
  validates :fingerprint, uniqueness: true
  validates :canonical_url, uniqueness: true

  scope :active, -> { where(lifecycle_state: lifecycle_states[:active]) }
  scope :recent_first, -> { order(Arel.sql("COALESCE(jobs.published_at, jobs.last_seen_at, jobs.created_at) DESC")) }

  before_validation :normalize_fields

  delegate :name, :slug, :host, to: :job_source, prefix: true

  def freshness_at
    published_at || last_seen_at || created_at
  end

  private
    def normalize_fields
      self.raw_payload ||= {}
      self.first_seen_at ||= Time.current
      self.last_seen_at ||= first_seen_at
      self.last_validated_at ||= last_seen_at
      self.apply_url = apply_url.to_s.delete_suffix("/")
      self.canonical_url = canonical_url.to_s.delete_suffix("/")
      self.source_url = source_url.to_s.delete_suffix("/")
      self.contract_type = JobContractTypeClassifier.call(
        title:,
        remote_text:,
        location_text:,
        posted_text:,
        raw_payload:
      )
    end
end
