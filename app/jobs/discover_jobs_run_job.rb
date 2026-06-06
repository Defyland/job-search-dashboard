class DiscoverJobsRunJob < ApplicationJob
  queue_as :default

  def perform(window_days: 20, trigger_source: :manual, source_slug: nil)
    source_scope = if source_slug.present?
      JobSource.backfillable.where(slug: source_slug)
    else
      JobSource.backfillable
    end

    JobDiscovery::Orchestrator.new(window_days:, trigger_source:, source_scope:).call
  end
end
