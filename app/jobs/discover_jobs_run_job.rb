class DiscoverJobsRunJob < ApplicationJob
  queue_as :default

  def perform(window_days: 20)
    JobDiscovery::Orchestrator.new(window_days:, trigger_source: :manual).call
  end
end
