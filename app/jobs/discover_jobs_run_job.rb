class DiscoverJobsRunJob < ApplicationJob
  queue_as :default

  def perform(window_days: 20, trigger_source: :manual, source_slug: nil, search_profile_id: nil)
    source_scope = if source_slug.present?
      JobSource.backfillable.where(slug: source_slug)
    else
      JobSource.backfillable
    end

    search_profiles = scoped_profiles(search_profile_id)
    return if search_profile_id.present? && search_profiles.blank?

    JobDiscovery::Orchestrator.new(
      window_days:,
      trigger_source:,
      source_scope:,
      search_profiles:
    ).call
  end

  private
    def scoped_profiles(search_profile_id)
      return nil if search_profile_id.blank?

      SearchProfile.active.where(id: search_profile_id).to_a
    end
end
