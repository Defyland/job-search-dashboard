class Api::V1::CodexFallbackSourcesController < Api::V1::BaseController
  def index
    render json: {
      sources: fallback_sources.map { |source| source_payload(source) },
      policy: policy_payload,
      search_index: search_index_payload,
      ingestion_endpoint: api_v1_job_ingestions_path
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
end
