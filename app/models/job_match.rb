class JobMatch < ApplicationRecord
  belongs_to :search_profile
  belongs_to :job

  enum :match_strength, { strong: 0, borderline: 1 }, prefix: true
  enum :user_state, { new_match: 0, seen: 1, applied: 2, ignored: 3 }, prefix: true

  validates :reason, presence: true
  validates :score, numericality: { greater_than_or_equal_to: 0 }
  validates :job_id, uniqueness: { scope: :search_profile_id }

  scope :recent_first, -> { order(first_seen_at: :desc, updated_at: :desc) }
  scope :highest_score_first, -> { order(score: :desc, updated_at: :desc) }
  scope :for_profile, ->(profile) { where(search_profile: profile) }

  before_validation :normalize_fields

  delegate :title,
           :company_name,
           :apply_url,
           :canonical_url,
           :source_url,
           :remote_text,
           :location_text,
           :posted_text,
           :published_at,
           :lifecycle_state,
           :lifecycle_state_active?,
           :lifecycle_state_expired?,
           :job_source,
           :job_source_name,
           :job_source_host,
           to: :job

  def freshness_at
    published_at || last_seen_at || created_at
  end

  private
    def normalize_fields
      self.stack_tags = normalize_list(stack_tags)
      self.eligibility_flags = normalize_list(eligibility_flags)
      self.raw_decision ||= {}
      self.seniority = seniority.presence || "senior"
      self.reason = reason.to_s.squish.presence || "match validado pela automacao"
      self.first_seen_at ||= Time.current
      self.last_seen_at ||= first_seen_at
      self.last_validated_at ||= last_seen_at
    end

    def normalize_list(values)
      Array(values).map { |value| value.to_s.downcase.squish }.reject(&:blank?).uniq
    end
end
