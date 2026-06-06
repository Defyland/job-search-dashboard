class Job < ApplicationRecord
  belongs_to :job_source

  has_many :search_run_items, dependent: :nullify
  has_many :discovered_jobs, dependent: :nullify

  enum :match_strength, { strong: 0, borderline: 1 }, prefix: true
  enum :user_state, { new_match: 0, seen: 1, applied: 2, ignored: 3 }, prefix: true
  enum :lifecycle_state, { active: 0, expired: 1 }, prefix: true

  normalizes :title, with: ->(value) { value.to_s.squish }
  normalizes :company_name, with: ->(value) { value.to_s.squish }
  normalizes :apply_url, with: ->(value) { value.to_s.strip }
  normalizes :canonical_url, with: ->(value) { value.to_s.strip }
  normalizes :source_url, with: ->(value) { value.to_s.strip }

  validates :title, :company_name, :apply_url, :canonical_url, :fingerprint, :reason, presence: true
  validates :fingerprint, uniqueness: true
  validates :canonical_url, uniqueness: true
  validates :score, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(lifecycle_state: lifecycle_states[:active]) }
  scope :recent_first, -> { order(Arel.sql("COALESCE(jobs.published_at, jobs.last_seen_at, jobs.created_at) DESC")) }
  scope :highest_score_first, -> { order(score: :desc, updated_at: :desc) }

  before_validation :normalize_fields

  delegate :name, :slug, :host, to: :job_source, prefix: true

  def stack_list
    stack_tags.join(", ")
  end

  def freshness_at
    published_at || last_seen_at || created_at
  end

  private
    def normalize_fields
      self.stack_tags = Array(stack_tags).map { |tag| tag.to_s.downcase.squish }.reject(&:blank?).uniq
      self.raw_payload ||= {}
      self.first_seen_at ||= Time.current
      self.last_seen_at ||= first_seen_at
      self.last_validated_at ||= last_seen_at
      self.apply_url = apply_url.to_s.delete_suffix("/")
      self.canonical_url = canonical_url.to_s.delete_suffix("/")
      self.source_url = source_url.to_s.delete_suffix("/")
    end
end
