module JobDiscovery
  class Orchestrator
    Result = Struct.new(:search_run, :summary, :errors, keyword_init: true) do
      def success?
        errors.blank?
      end
    end

    def initialize(
      window_days:,
      trigger_source: :manual,
      source_scope: JobSource.backfillable,
      registry: JobDiscovery::Registry.new,
      search_profiles: nil,
      search_index_seeder_class: JobDiscovery::SearchIndex::BoardSeeder
    )
      @window_days = window_days.to_i.positive? ? window_days.to_i : 20
      @trigger_source = trigger_source
      @source_scope = source_scope
      @registry = registry
      @search_profiles = Array(search_profiles).compact
      @search_index_seeder_class = search_index_seeder_class
      @errors = []
    end

    def call
      search_run = SearchRun.create!(
        trigger_source: @trigger_source,
        status: :running,
        window_label: "#{@window_days}d",
        started_at: Time.current,
        summary: run_summary
      )
      search_run.update!(summary: search_run.summary.merge(search_index: seed_search_index))

      recorder = JobIngestions::Recorder.new(search_run:, profiles: @search_profiles.presence)
      discovery_counts = { discovered_count: 0, source_scans_count: 0 }

      @source_scope.order(priority: :asc, name: :asc).each do |source|
        discovery_counts[:source_scans_count] += 1
        unless @registry.supports?(source.adapter_key)
          mark_unsupported_source!(search_run:, source:)
          next
        end

        scan_source(search_run:, source:, recorder:, discovery_counts:)
      end

      summary = recorder.summary.merge(discovery_counts)
      status = final_status(search_run, summary)

      search_run.update!(
        status:,
        finished_at: Time.current,
        imported_count: summary[:imported_count],
        updated_count: summary[:updated_count],
        expired_count: summary[:expired_count],
        rejected_count: summary[:rejected_count],
        error_message: @errors.presence&.join(" | "),
        summary: search_run.summary.merge(summary)
      )

      Result.new(search_run:, summary:, errors: @errors)
    rescue StandardError => error
      search_run&.update(status: :failed, finished_at: Time.current, error_message: error.message)
      Result.new(search_run:, summary: {}, errors: [ error.message ])
    end

    private
      def run_summary
        {
          discovery_mode: "rails",
          window_days: @window_days,
          search_profile_ids: @search_profiles.map(&:id)
        }.compact
      end

      def scan_source(search_run:, source:, recorder:, discovery_counts:)
        source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
        adapter = @registry.fetch(source.adapter_key).new(policy: scoped_policy)
        candidates = adapter.scan(source_scan:, window_days: @window_days)

        persist_scan_results(search_run:, source_scan:, source:, recorder:, discovery_counts:, candidates:)
      rescue StandardError => error
        @errors << "#{source.name}: #{error.message}"
        raise unless source_scan

        source_scan.update!(status: :failed, finished_at: Time.current, error_message: error.message)
      end

      def persist_scan_results(search_run:, source_scan:, source:, recorder:, discovery_counts:, candidates:)
        SourceScan.transaction do
          accepted_jobs = []
          rejected_jobs = []
          counts = { accepted_count: 0, borderline_count: 0, rejected_count: 0, expired_count: 0 }
          local_discovered_count = 0

          candidates.each do |candidate|
            discovered_job = persist_discovered_job(search_run:, source_scan:, source:, candidate:)
            local_discovered_count += 1

            case discovered_job.classification
            when "strong"
              counts[:accepted_count] += 1
              accepted_jobs << ingestion_payload_for(discovered_job, "strong")
            when "borderline"
              counts[:borderline_count] += 1
              accepted_jobs << ingestion_payload_for(discovered_job, "borderline")
            when "expired"
              counts[:expired_count] += 1
              rejected_jobs << { title: discovered_job.title, company: discovered_job.company_name, reason: discovered_job.reason }
            else
              counts[:rejected_count] += 1
              rejected_jobs << { title: discovered_job.title, company: discovered_job.company_name, reason: discovered_job.exclusion_reason.presence || discovered_job.reason }
            end
          end

          recorder.record_jobs(accepted_jobs)
          recorder.record_rejections(rejected_jobs)
          link_discovered_jobs!(source_scan)
          discovery_counts[:discovered_count] += local_discovered_count

          source.update!(last_full_scan_at: Time.current)
          source_scan.update!(
            status: counts.values.sum.zero? ? :exhausted : :succeeded,
            finished_at: Time.current,
            candidates_seen: candidates.size,
            accepted_count: counts[:accepted_count],
            borderline_count: counts[:borderline_count],
            rejected_count: counts[:rejected_count],
            expired_count: counts[:expired_count]
          )
        end
      end

      def seed_search_index
        @search_index_seeder_class.new(
          search_profiles: profiles_for_search_index,
          sources: @source_scope
        ).call.to_h
      rescue StandardError => error
        {
          enabled: JobDiscovery::SearchIndex::Client.configured?,
          query_count: 0,
          result_count: 0,
          seeded_count: 0,
          errors: [ error.message ]
        }
      end

      def profiles_for_search_index
        @search_profiles.presence || SearchProfile.active.ordered.to_a
      end

      def mark_unsupported_source!(search_run:, source:)
        message = "adapter #{source.adapter_key} nao suportado"
        @errors << "#{source.name}: #{message}"
        search_run.source_scans.create!(
          job_source: source,
          status: :failed,
          started_at: Time.current,
          finished_at: Time.current,
          error_message: message
        )
      end

      def persist_discovered_job(search_run:, source_scan:, source:, candidate:)
        source_scan.discovered_jobs.create!(
          search_run:,
          job_source: source,
          classification: candidate.fetch(:classification),
          title: candidate[:title],
          company_name: candidate[:company_name],
          apply_url: candidate[:apply_url],
          canonical_url: candidate[:canonical_url],
          source_url: candidate[:source_url],
          external_job_id: candidate[:external_job_id],
          fingerprint: candidate[:fingerprint],
          remote_text: candidate[:remote_text],
          location_text: candidate[:location_text],
          seniority: candidate[:seniority],
          reason: candidate[:reason],
          exclusion_reason: candidate[:exclusion_reason],
          score: candidate[:score],
          published_at: candidate[:published_at],
          posted_text: candidate[:posted_text],
          stack_tags: candidate[:stack_tags],
          payload: candidate_payload(candidate)
        )
      end

      def ingestion_payload_for(discovered_job, match_strength)
        discovered_job.ingestion_payload(match_strength:)
      end

      def candidate_payload(candidate)
        candidate[:payload].to_h.merge(description: candidate[:description], eligibility_flags: candidate[:eligibility_flags])
      end

      def link_discovered_jobs!(source_scan)
        candidates = source_scan.discovered_jobs.where(job_id: nil).to_a
        return if candidates.empty?

        # Resolve every candidate's canonical Job in two queries instead of two per row,
        # keeping the same fingerprint-first, canonical-url fallback identity rule as Job.find_duplicate.
        jobs = Job.where(fingerprint: candidates.filter_map(&:fingerprint))
                  .or(Job.where(canonical_url: candidates.filter_map(&:canonical_url)))
        jobs_by_fingerprint = jobs.index_by(&:fingerprint)
        jobs_by_canonical_url = jobs.index_by(&:canonical_url)

        candidates.each do |candidate|
          job = jobs_by_fingerprint[candidate.fingerprint] || jobs_by_canonical_url[candidate.canonical_url]
          candidate.update_column(:job_id, job.id) if job
        end
      end

      def final_status(search_run, summary)
        return :failed if search_run.source_scans.status_failed.exists? && summary[:imported_count].zero? && summary[:updated_count].zero?
        return :partial if search_run.source_scans.status_failed.exists?

        :succeeded
      end

      def scoped_policy
        @scoped_policy ||= JobDiscovery::Policy.new(search_profiles: @search_profiles.presence)
      end
  end
end
