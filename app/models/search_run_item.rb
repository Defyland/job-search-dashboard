class SearchRunItem < ApplicationRecord
  belongs_to :search_run
  belongs_to :job, optional: true

  enum :outcome, { created: 0, updated: 1, skipped: 2, rejected: 3, expired: 4, failed: 5 }, prefix: true

  before_validation :apply_defaults

  private
    def apply_defaults
      self.payload ||= {}
      self.reason ||= ""
    end
end
