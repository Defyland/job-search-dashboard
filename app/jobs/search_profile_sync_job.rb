class SearchProfileSyncJob < ApplicationJob
  queue_as :default

  def perform(search_profile_id:, prune_stale: false)
    search_profile = SearchProfile.find_by(id: search_profile_id)
    return unless search_profile

    return mark_idle(search_profile) unless search_profile.active?

    search_profile.update!(sync_state: :syncing, last_sync_error: nil)
    result = SearchProfiles::Sync.new(search_profile:, prune_stale:).call

    if result.success?
      search_profile.update!(
        sync_state: :synced,
        last_synced_at: Time.current,
        last_sync_error: nil
      )
    else
      search_profile.update!(
        sync_state: :failed,
        last_sync_error: result.errors.join(" | ")
      )
    end
  rescue StandardError => error
    search_profile&.update!(
      sync_state: :failed,
      last_sync_error: error.message
    )
    raise
  end

  private
    def mark_idle(search_profile)
      search_profile.update!(sync_state: :idle, last_sync_error: nil)
    end
end
