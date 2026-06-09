module SearchProfiles
  class SyncRequest
    Error = Class.new(StandardError)

    def initialize(search_profile:, prune_stale:, job_class: SearchProfileSyncJob)
      @search_profile = search_profile
      @prune_stale = prune_stale
      @job_class = job_class
    end

    def call
      return mark_idle! unless @search_profile.active?

      @search_profile.update!(
        sync_state: :pending,
        last_sync_requested_at: Time.current,
        last_sync_error: nil
      )
      @job_class.perform_later(search_profile_id: @search_profile.id, prune_stale: @prune_stale)
    rescue StandardError => error
      raise Error, "Nao foi possivel enfileirar a busca agora: #{error.message}"
    end

    private
      def mark_idle!
        @search_profile.update!(
          sync_state: :idle,
          last_sync_error: nil
        )
      end
  end
end
