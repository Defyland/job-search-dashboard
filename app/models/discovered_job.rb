class DiscoveredJob < ApplicationRecord
  belongs_to :search_run
  belongs_to :source_scan
  belongs_to :job_source
  belongs_to :job, optional: true

  enum :classification, { strong: 0, borderline: 1, rejected: 2, expired: 3 }, prefix: true

  normalizes :title, with: ->(value) { value.to_s.squish }
  normalizes :company_name, with: ->(value) { value.to_s.squish }
  normalizes :apply_url, with: ->(value) { value.to_s.strip }
  normalizes :canonical_url, with: ->(value) { value.to_s.strip }
  normalizes :source_url, with: ->(value) { value.to_s.strip }

  validates :classification, :fingerprint, presence: true
  validates :fingerprint, uniqueness: { scope: :source_scan_id }

  before_validation :apply_defaults

  def accepted?
    classification_strong? || classification_borderline?
  end

  private
    def apply_defaults
      self.stack_tags = Array(stack_tags).map { |tag| tag.to_s.downcase.squish }.reject(&:blank?).uniq
      self.payload ||= {}
      self.score ||= 0
      self.seniority = seniority.presence || "senior"
      self.apply_url = apply_url.to_s.delete_suffix("/")
      self.canonical_url = canonical_url.to_s.delete_suffix("/")
      self.source_url = source_url.to_s.delete_suffix("/")
    end
end
