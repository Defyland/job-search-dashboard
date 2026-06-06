class SourceScan < ApplicationRecord
  enum :status, { pending: 0, running: 1, succeeded: 2, partial: 3, failed: 4, exhausted: 5 }, prefix: true

  belongs_to :search_run
  belongs_to :job_source

  has_many :discovered_jobs, dependent: :destroy

  validates :job_source_id, uniqueness: { scope: :search_run_id }

  before_validation :apply_defaults

  def record_page!
    increment!(:pages_scanned)
  end

  private
    def apply_defaults
      self.status ||= :pending
      self.metadata ||= {}
      self.started_at ||= Time.current if status_running?
    end
end
