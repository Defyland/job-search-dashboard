module JobIngestions
  class Importer
    Result = Struct.new(:search_run, :summary, :errors, :replayed, :conflict, keyword_init: true) do
      def success?
        errors.blank?
      end
    end

    def initialize(payload:, profiles: nil)
      @payload = payload.deep_stringify_keys
      @profiles = Array(profiles).compact
      @summary = {
        imported_count: 0,
        updated_count: 0,
        expired_count: 0,
        rejected_count: 0
      }
    end

    def call
      return Result.new(search_run: nil, summary: @summary, errors: validation_errors, replayed: false) if validation_errors.any?

      existing_run = find_client_run
      return replay_or_conflict(existing_run) if existing_run

      create_search_run
    rescue ActiveRecord::RecordNotUnique => error
      raise unless client_run_conflict?(error)

      # The winner committed after our insert blocked on the index; our transaction is already rolled back.
      replay_or_conflict(SearchRun.find_by!(client_run_id:))
    rescue ActiveRecord::RecordInvalid => error
      record_failed_run(error.message)
    end

    def request_digest
      @request_digest ||= Digest::SHA256.hexdigest(JSON.generate(canonicalize(@payload)))
    end

    private
      def validation_errors
        errors = []
        errors << "jobs must be an array" unless normalized_jobs.is_a?(Array)
        errors << "jobs must contain objects" unless normalized_jobs.all? { |item| item.is_a?(Hash) }
        errors << "run window must be present" if normalize_window_label.blank?
        errors << "run.client_run_id must be a string" unless client_run_id.nil? || client_run_id.is_a?(String)
        errors
      end

      def create_search_run
        SearchRun.transaction do
          @search_run = SearchRun.create!(
            trigger_source: normalize_trigger_source,
            status: :running,
            window_label: normalize_window_label,
            started_at: normalize_started_at,
            summary: run_metadata,
            **idempotency_attributes
          )

          recorder = JobIngestions::Recorder.new(search_run: @search_run, profiles: @profiles.presence)
          recorder.record_jobs(normalized_jobs)
          recorder.record_rejections(normalized_rejections)
          mark_codex_fallback_sources_checked!
          @summary = recorder.summary

          @search_run.update!(
            status: final_status,
            finished_at: Time.current,
            imported_count: @summary[:imported_count],
            updated_count: @summary[:updated_count],
            expired_count: @summary[:expired_count],
            rejected_count: @summary[:rejected_count],
            summary: run_metadata.merge(@summary)
          )
        end

        Result.new(search_run: @search_run, summary: @summary, errors: [], replayed: false)
      end

      def record_failed_run(message)
        # A keyed run rolled back with its transaction; saving it again would re-insert the row and keep its client_run_id.
        return Result.new(search_run: nil, summary: @summary, errors: [ message ], replayed: false) if client_run_id

        @search_run&.update(status: :failed, finished_at: Time.current, error_message: message)
        Result.new(search_run: @search_run, summary: @summary, errors: [ message ], replayed: false)
      end

      def find_client_run
        return if client_run_id.nil?

        SearchRun.find_by(client_run_id:)
      end

      def replay_or_conflict(run)
        if run.request_digest == request_digest
          Result.new(search_run: run, summary: counters_for(run), errors: [], replayed: true)
        else
          Result.new(
            search_run: nil,
            summary: @summary,
            errors: [ "client_run_id #{client_run_id} was already used with a different payload" ],
            replayed: false,
            conflict: true
          )
        end
      end

      def client_run_conflict?(error)
        client_run_id.present? &&
          error.cause.is_a?(PG::UniqueViolation) &&
          error.cause.result&.error_field(PG::PG_DIAG_CONSTRAINT_NAME) == SearchRun::CLIENT_RUN_INDEX
      end

      def idempotency_attributes
        return {} if client_run_id.nil?

        { client_run_id:, request_digest: }
      end

      def counters_for(run)
        {
          imported_count: run.imported_count,
          updated_count: run.updated_count,
          expired_count: run.expired_count,
          rejected_count: run.rejected_count
        }
      end

      def client_run_id
        return @client_run_id if defined?(@client_run_id)

        @client_run_id = run_metadata["client_run_id"].presence
      end

      def canonicalize(value)
        case value
        when Hash then value.sort_by { |key, _| key.to_s }.to_h { |key, item| [ key.to_s, canonicalize(item) ] }
        when Array then value.map { |item| canonicalize(item) }
        else value
        end
      end

      def normalize_window_label
        run_metadata["window_label"].presence || @payload["window"].presence || "24h"
      end

      def normalize_trigger_source
        raw_value = run_metadata["trigger_source"].presence || @payload["trigger_source"].presence || "codex_automation"
        SearchRun.trigger_sources.fetch(raw_value, SearchRun.trigger_sources.fetch("codex_automation"))
      end

      def normalize_started_at
        parse_time(run_metadata["started_at"]) || Time.current
      end

      def normalized_jobs
        return @normalized_jobs if defined?(@normalized_jobs)

        direct_jobs = Array(@payload["jobs"])
        strong_jobs = Array(@payload["strong_matches"]) + Array(@payload["matches_strong"])
        borderline_jobs = Array(@payload["borderline_matches"]) + Array(@payload["borderline"])

        @normalized_jobs =
          if direct_jobs.any?
            direct_jobs
          else
            strong_jobs.map { |item| item.merge("match_strength" => "strong") } +
              borderline_jobs.map { |item| item.merge("match_strength" => "borderline") }
          end
      end

      def normalized_rejections
        Array(@payload["rejections"])
      end

      def mark_codex_fallback_sources_checked!
        return unless @search_run.trigger_source_codex_automation?

        slugs = codex_fallback_source_slugs
        return if slugs.blank?

        JobSource.codex_fallback.where(slug: slugs).update_all(last_codex_checked_at: Time.current)
      end

      def codex_fallback_source_slugs
        [
          run_metadata["source_slug"],
          Array(run_metadata["source_slugs"]),
          Array(@payload["source_slugs"]),
          normalized_jobs,
          normalized_rejections
        ].flatten.filter_map do |item|
          case item
          when Hash
            item["source_slug"].presence || item[:source_slug].presence
          else
            item.presence
          end
        end.map { |value| value.to_s.parameterize }.uniq
      end

      def final_status
        @summary[:rejected_count].positive? && (@summary[:imported_count].positive? || @summary[:updated_count].positive?) ? :partial : :succeeded
      end

      def run_metadata
        @run_metadata ||= @payload.fetch("run", {}).deep_stringify_keys
      end

      def parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
  end
end
