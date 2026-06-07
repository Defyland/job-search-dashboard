module JobDiscovery
  class Orchestrator
    Result = Struct.new(:search_run, :summary, :errors, keyword_init: true) do
      def success?
        errors.blank?
      end
    end

    def initialize(window_days:, trigger_source: :manual, source_scope: JobSource.backfillable, registry: JobDiscovery::Registry.new)
      @window_days = window_days.to_i.positive? ? window_days.to_i : 20
      @trigger_source = trigger_source
      @source_scope = source_scope
      @registry = registry
      @errors = []
    end

    def call
      search_run = SearchRun.create!(
        trigger_source: @trigger_source,
        status: :running,
        window_label: "#{@window_days}d",
        started_at: Time.current,
        summary: { discovery_mode: "rails", window_days: @window_days }
      )

      recorder = JobIngestions::Recorder.new(search_run:)
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
      def scan_source(search_run:, source:, recorder:, discovery_counts:)
        source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
        SourceScan.transaction do
          adapter = @registry.fetch(source.adapter_key).new
          candidates = adapter.scan(source_scan:, window_days: @window_days)

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
      rescue StandardError => error
        @errors << "#{source.name}: #{error.message}"
        source_scan.update!(status: :failed, finished_at: Time.current, error_message: error.message)
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
        {
          title: discovered_job.title,
          company: discovered_job.company_name,
          apply_url: discovered_job.apply_url,
          canonical_url: discovered_job.canonical_url,
          source_url: discovered_job.source_url,
          source_name: discovered_job.job_source.name,
          source_slug: discovered_job.job_source.slug,
          source_kind: discovered_job.job_source.source_kind,
          external_job_id: discovered_job.external_job_id,
          remote_signal: discovered_job.remote_text,
          location: discovered_job.location_text,
          seniority: discovered_job.seniority,
          match_strength:,
          reason: discovered_job.reason,
          score: discovered_job.score,
          recency_text: discovered_job.posted_text,
          published_at: discovered_job.published_at&.iso8601,
          stack_tags: discovered_job.stack_tags,
          fingerprint: discovered_job.fingerprint,
          description: discovered_job.payload["description"]
        }
      end

      def candidate_payload(candidate)
        candidate[:payload].to_h.merge(description: candidate[:description])
      end

      def link_discovered_jobs!(source_scan)
        source_scan.discovered_jobs.where(job_id: nil).find_each do |candidate|
          job = Job.find_by(fingerprint: candidate.fingerprint) || Job.find_by(canonical_url: candidate.canonical_url)
          candidate.update_column(:job_id, job.id) if job
        end
      end

      def final_status(search_run, summary)
        return :failed if search_run.source_scans.status_failed.exists? && summary[:imported_count].zero? && summary[:updated_count].zero?
        return :partial if search_run.source_scans.status_failed.exists?

        :succeeded
      end
  end
end
