module SearchProfiles
  class Sync
    Result = Struct.new(:discovered_bootstrap_result, :external_run_enqueued, :errors, keyword_init: true) do
      def success?
        errors.blank?
      end
    end

    def initialize(
      search_profile:,
      prune_stale: false,
      bootstrapper_class: SearchProfiles::Bootstrapper,
      discovered_bootstrapper_class: SearchProfiles::DiscoveredBootstrapper,
      run_job_class: DiscoverJobsRunJob
    )
      @search_profile = search_profile
      @prune_stale = prune_stale
      @bootstrapper_class = bootstrapper_class
      @discovered_bootstrapper_class = discovered_bootstrapper_class
      @run_job_class = run_job_class
    end

    def call
      return Result.new(discovered_bootstrap_result: nil, external_run_enqueued: false, errors: []) unless @search_profile.active?

      @bootstrapper_class.new(search_profile: @search_profile, prune_stale: @prune_stale).call
      discovered_bootstrap_result = @discovered_bootstrapper_class.new(search_profile: @search_profile).call
      @run_job_class.perform_later(
        window_days: @search_profile.scan_window_days,
        trigger_source: :manual,
        search_profile_id: @search_profile.id
      )

      Result.new(
        discovered_bootstrap_result:,
        external_run_enqueued: true,
        errors: Array(discovered_bootstrap_result&.errors).compact
      )
    end
  end
end
