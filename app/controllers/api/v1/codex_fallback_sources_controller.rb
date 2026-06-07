class Api::V1::CodexFallbackSourcesController < Api::V1::BaseController
  def index
    render json: {
      sources: fallback_sources.map { |source| source_payload(source) },
      policy: policy_payload,
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
        last_codex_fallback_at: source.last_codex_fallback_at&.iso8601,
        settings: source.settings
      }
    end

    def policy_payload
      {
        seniority_terms: %w[senior sênior sr staff],
        stack_terms: [ "ruby", "ruby on rails", "rails", "react", "react native", "frontend", "fullstack" ],
        location_priority: "remote compatible with Brazil or LatAm",
        exclude_terms: [ "junior", "júnior", "pleno", "mid-level", "trainee", "intern", "internship", "estágio", "mulheres", "women only" ],
        output: "POST accepted strong/borderline jobs and useful rejections to /api/v1/job_ingestions"
      }
    end
end
