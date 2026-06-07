module JobIngestions
  class Importer
    Result = Struct.new(:search_run, :summary, :errors, keyword_init: true) do
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
      return Result.new(search_run: nil, summary: @summary, errors: validation_errors) if validation_errors.any?

      SearchRun.transaction do
        @search_run = SearchRun.create!(
          trigger_source: normalize_trigger_source,
          status: :running,
          window_label: normalize_window_label,
          started_at: normalize_started_at,
          summary: run_metadata
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

      Result.new(search_run: @search_run, summary: @summary, errors: [])
    rescue ActiveRecord::RecordInvalid => error
      @search_run&.update(status: :failed, finished_at: Time.current, error_message: error.message)
      Result.new(search_run: @search_run, summary: @summary, errors: [ error.message ])
    end

    private
      def validation_errors
        errors = []
        errors << "jobs must be an array" unless normalized_jobs.is_a?(Array)
        errors << "run window must be present" if normalize_window_label.blank?
        errors
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
