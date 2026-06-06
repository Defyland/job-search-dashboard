class JobFilters
  def initialize(scope:, params:)
    @scope = scope
    @params = params
  end

  def call
    filtered_scope = @scope.references(:job_source)

    filtered_scope = apply_text_search(filtered_scope)
    filtered_scope = apply_stack_filter(filtered_scope)
    filtered_scope = apply_source_filter(filtered_scope)
    filtered_scope = apply_match_strength_filter(filtered_scope)
    filtered_scope = apply_user_state_filter(filtered_scope)
    filtered_scope = apply_lifecycle_filter(filtered_scope)
    filtered_scope = apply_recency_filter(filtered_scope)
    apply_sort(filtered_scope)
  end

  private
    def apply_text_search(scope)
      return scope if @params[:q].blank?

      query = "%#{@params[:q].to_s.strip}%"

      scope.joins(:job_source).where(
        "jobs.title ILIKE :query OR jobs.company_name ILIKE :query OR jobs.reason ILIKE :query OR job_sources.name ILIKE :query",
        query:
      )
    end

    def apply_stack_filter(scope)
      return scope if @params[:stack].blank?

      scope.where("EXISTS (SELECT 1 FROM unnest(jobs.stack_tags) AS tag WHERE tag = ?)", @params[:stack].to_s.downcase)
    end

    def apply_source_filter(scope)
      return scope if @params[:source].blank?

      scope.joins(:job_source).where(job_sources: { slug: @params[:source] })
    end

    def apply_match_strength_filter(scope)
      return scope if @params[:match_strength].blank? || @params[:match_strength] == "all"
      return scope unless Job.match_strengths.key?(@params[:match_strength])

      scope.where(match_strength: Job.match_strengths.fetch(@params[:match_strength]))
    end

    def apply_user_state_filter(scope)
      return scope if @params[:user_state].blank? || @params[:user_state] == "all"
      return scope unless Job.user_states.key?(@params[:user_state])

      scope.where(user_state: Job.user_states.fetch(@params[:user_state]))
    end

    def apply_lifecycle_filter(scope)
      lifecycle = @params[:lifecycle_state].presence || "active"
      return scope if lifecycle == "all"
      return scope unless Job.lifecycle_states.key?(lifecycle)

      scope.where(lifecycle_state: Job.lifecycle_states.fetch(lifecycle))
    end

    def apply_recency_filter(scope)
      return scope if @params[:recency].blank? || @params[:recency] == "all"

      threshold =
        case @params[:recency]
        when "24h" then 24.hours.ago
        when "7d" then 7.days.ago
        when "14d" then 14.days.ago
        when "30d" then 30.days.ago
        end

      return scope unless threshold

      scope.where("COALESCE(jobs.published_at, jobs.last_seen_at, jobs.created_at) >= ?", threshold)
    end

    def apply_sort(scope)
      case @params[:sort]
      when "score"
        scope.highest_score_first
      when "company"
        scope.order(company_name: :asc, title: :asc)
      when "updated"
        scope.order(updated_at: :desc)
      else
        scope.recent_first
      end
    end
end
