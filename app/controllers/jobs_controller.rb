class JobsController < ApplicationController
  before_action :set_job, only: %i[show mark]

  def index
    @filters = filter_params.to_h.symbolize_keys
    @source_options = JobSource.order(priority: :asc, name: :asc)
    filtered_scope = JobFilters.new(scope: Job.includes(:job_source), params: @filters).call

    @counts = {
      active: Job.active.count,
      new_match: Job.active.user_state_new_match.count,
      applied: Job.user_state_applied.count,
      borderline: Job.active.match_strength_borderline.count
    }

    @per_page = 25
    @total_jobs = filtered_scope.count
    @total_pages = [ (@total_jobs.to_f / @per_page).ceil, 1 ].max
    @page = [ [ params.fetch(:page, 1).to_i, 1 ].max, @total_pages ].min
    @jobs = filtered_scope.limit(@per_page).offset((@page - 1) * @per_page)
  end

  def show
    @history = @job.search_run_items.includes(:search_run).order(created_at: :desc).limit(20)
  end

  def mark
    state = params.require(:user_state)

    unless Job.user_states.key?(state)
      redirect_back fallback_location: jobs_path, alert: "Status invalido."
      return
    end

    @job.update!(user_state: state)
    redirect_back fallback_location: job_path(@job), notice: "Status atualizado."
  end

  private
    def filter_params
      params.permit(:q, :stack, :source, :match_strength, :user_state, :lifecycle_state, :recency, :sort)
    end

    def set_job
      @job = Job.includes(:job_source).find(params[:id])
    end
end
