module SearchProfiles
  class Bootstrapper
    def initialize(search_profile:, job_scope: Job.includes(:job_source), prune_stale: false)
      @search_profile = search_profile
      @job_scope = job_scope
      @prune_stale = prune_stale
      @policy = JobDiscovery::Policy.new(search_profile: @search_profile)
    end

    def call
      accepted_job_ids = []

      @job_scope.find_each.sum do |job|
        decision = classify(job)
        next 0 unless decision.accepted?

        accepted_job_ids << job.id
        JobMatches::Upserter.call(job:, decision:, timestamp: Time.current)
        1
      end.tap do
        prune_stale_matches!(accepted_job_ids) if @prune_stale
      end
    end

    private
      def prune_stale_matches!(accepted_job_ids)
        stale_scope = @search_profile.job_matches
        stale_scope = stale_scope.where.not(job_id: accepted_job_ids) if accepted_job_ids.any?
        stale_scope.delete_all
      end

      def classify(job)
        @policy.classify(
          title: job.title,
          remote_text: job.remote_text,
          location_text: job.location_text,
          description: description_for(job),
          source_slug: job.job_source&.slug,
          posted_text: job.posted_text,
          published_at: job.published_at
        )
      end

      def description_for(job)
        payload = job.raw_payload.deep_stringify_keys

        [
          payload["description"],
          payload["body"],
          payload["requirements"],
          payload["summary"]
        ].compact.join(" ")
      end
  end
end
