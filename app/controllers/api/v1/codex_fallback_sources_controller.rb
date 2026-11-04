class Api::V1::CodexFallbackSourcesController < Api::V1::BaseController
  def index
    render json: {
      sources: fallback_sources.map { |source| source_payload(source) },
      policy: policy_payload,
      search_index: search_index_payload,
      ingestion_endpoint: api_v1_job_ingestions_path,
      coverage: {
        native_sources: native_sources_payload,
        last_successful_codex_run: last_successful_codex_run_payload
      }
    }
  end

  private
    def fallback_sources
      JobSource.codex_fallback.order(priority: :asc, name: :asc)
    end

    def source_payload(source)
      {
        name: source.name,
        slug: source.slug,
        kind: source.source_kind,
        base_url: source.base_url,
        host: source.host,
        scan_window_days: source.scan_window_days,
        reason: source.codex_fallback_reason,
        last_codex_checked_at: source.last_codex_checked_at&.iso8601,
        last_codex_fallback_at: source.last_codex_fallback_at&.iso8601,
        settings: source.settings
      }
    end

    def policy_payload
      JobDiscovery::Policy.contract
    end

    def search_index_payload
      {
        rails_native_enabled: JobDiscovery::SearchIndex::Client.configured?,
        provider: ENV.fetch("SEARCH_INDEX_PROVIDER", "serpapi"),
        queries: JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: SearchProfile.active.ordered.to_a)
                                                        .queries
                                                        .map(&:to_h)
      }
    end

    def native_sources_payload
      JobSource.backfillable.order(priority: :asc, name: :asc).map do |source|
        {
          slug: source.slug,
          host: source.host,
          last_full_scan_at: source.last_full_scan_at&.iso8601,
          known_boards: known_boards_payload(source)
        }
      end
    end

    # Only the setting keys the search index already queries for this slug are exposed,
    # so clients can skip known boards without seeing the rest of the source settings.
    def known_boards_payload(source)
      settings = source.settings.to_h
      setting_keys = JobDiscovery::SearchIndex::QueryBuilder::TARGETS
        .select { |target| target[:source_slug] == source.slug }
        .filter_map { |target| target[:setting_key] }
        .uniq

      setting_keys.each_with_object({}) do |key, boards|
        values = Array(settings[key]).map { |value| value.to_s.strip }.reject(&:blank?).uniq.sort
        boards[key] = values if values.any?
      end
    end

    def last_successful_codex_run_payload
      run = SearchRun.trigger_source_codex_automation
                     .where(status: [ :succeeded, :partial ])
                     .where.not(finished_at: nil)
                     .order(finished_at: :desc, id: :desc)
                     .first
      return unless run

      {
        id: run.id,
        status: run.status,
        started_at: run.started_at.iso8601,
        finished_at: run.finished_at.iso8601,
        window_label: run.window_label
      }
    end
end
