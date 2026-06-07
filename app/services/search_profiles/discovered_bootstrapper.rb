module SearchProfiles
  class DiscoveredBootstrapper
    def initialize(search_profile:, importer_class: JobIngestions::Importer, window_days: nil)
      @search_profile = search_profile
      @importer_class = importer_class
      @window_days = window_days.to_i.positive? ? window_days.to_i : search_profile.scan_window_days
    end

    def call
      jobs = candidate_payloads
      return if jobs.empty?

      @importer_class.new(
        payload: {
          run: {
            window_label: "#{@window_days}d",
            trigger_source: "manual",
            started_at: Time.current.iso8601,
            discovery_mode: "discovered_cache",
            search_profile_id: @search_profile.id
          },
          jobs:
        },
        profiles: [ @search_profile ]
      ).call
    end

    private
      def candidate_payloads
        seen_keys = {}

        discovered_scope.filter_map do |candidate|
          key = candidate.fingerprint.presence || candidate.canonical_url
          next if key.blank? || seen_keys[key]

          seen_keys[key] = true
          payload_for(candidate)
        end
      end

      def discovered_scope
        DiscoveredJob.includes(:job_source)
          .joins(:search_run)
          .where(job_id: nil)
          .where.not(classification: DiscoveredJob.classifications.fetch("expired"))
          .where("search_runs.started_at >= ?", @window_days.days.ago)
          .order("search_runs.started_at DESC", "discovered_jobs.id DESC")
      end

      def payload_for(candidate)
        {
          title: candidate.title,
          company: candidate.company_name,
          apply_url: candidate.apply_url,
          canonical_url: candidate.canonical_url,
          source_url: candidate.source_url,
          source_name: candidate.job_source.name,
          source_slug: candidate.job_source.slug,
          source_kind: candidate.job_source.source_kind,
          external_job_id: candidate.external_job_id,
          remote_signal: candidate.remote_text,
          location: candidate.location_text,
          seniority: candidate.seniority,
          reason: candidate.reason,
          recency_text: candidate.posted_text,
          published_at: candidate.published_at&.iso8601,
          stack_tags: candidate.stack_tags,
          fingerprint: candidate.fingerprint,
          description: candidate.payload["description"].presence || candidate.payload["body"].presence || candidate.payload["summary"].presence
        }
      end
  end
end
