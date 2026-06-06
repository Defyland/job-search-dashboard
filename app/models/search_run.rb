class SearchRun < ApplicationRecord
  enum :trigger_source, { codex_automation: 0, manual: 1, cron: 2 }, prefix: true
  enum :status, { pending: 0, running: 1, succeeded: 2, failed: 3, partial: 4 }, prefix: true

  has_many :search_run_items, dependent: :destroy
  has_many :source_scans, dependent: :destroy
  has_many :discovered_jobs, dependent: :destroy

  validates :window_label, presence: true

  before_validation :apply_defaults

  def duration_seconds
    return unless started_at && finished_at

    (finished_at - started_at).to_i
  end

  private
    def apply_defaults
      self.started_at ||= Time.current
      self.summary ||= {}
    end
end
