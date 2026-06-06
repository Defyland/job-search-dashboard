class DiscoverJobsRunJob < ApplicationJob
  queue_as :default

  def perform(window_days: 20, trigger_source: :manual)
    JobDiscovery::Orchestrator.new(window_days:, trigger_source:).call
  end
end
