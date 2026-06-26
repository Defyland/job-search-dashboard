class JobsController < ApplicationController
  before_action :ensure_search_profile!, only: %i[index show open mark]
  before_action :set_search_profile
  before_action :set_job, only: %i[show open mark]

  def index
    @filters = filter_params.to_h.symbolize_keys
    @filters[:user_state] = "new_match" if @filters[:user_state].blank?
    @source_options = JobSource.order(priority: :asc, name: :asc)
    @search_profiles = current_user.search_profiles.ordered
    @stack_options = @search_profile.target_stacks
    @title_language_options = JobTitleLanguage::FILTER_OPTIONS
    base_scope = JobMatch.for_profile(@search_profile).includes(job: :job_source)
    filtered_scope = JobMatchFilters.new(scope: base_scope, params: @filters).call
    @has_any_matches = base_scope.exists?

    @counts = {
      active: base_scope.joins(:job).where(jobs: { lifecycle_state: Job.lifecycle_states.fetch("active") }).count,
      new_match: base_scope.joins(:job).where(jobs: { lifecycle_state: Job.lifecycle_states.fetch("active") }).user_state_new_match.count,
      applied: base_scope.user_state_applied.count,
      borderline: base_scope.joins(:job).where(jobs: { lifecycle_state: Job.lifecycle_states.fetch("active") }).match_strength_borderline.count
    }

    @per_page = 25
    @total_matches = filtered_scope.count
    @total_pages = [ (@total_matches.to_f / @per_page).ceil, 1 ].max
    @page = [ [ params.fetch(:page, 1).to_i, 1 ].max, @total_pages ].min
    @job_matches = filtered_scope.limit(@per_page).offset((@page - 1) * @per_page)
  end

  def show
    @job_match = @job.job_matches.find_by!(search_profile: @search_profile)
    @history = @job.search_run_items.includes(:search_run).order(created_at: :desc).limit(20)
  end

  def open
    @apply_url = @job.safe_apply_url

    unless @apply_url
      redirect_back fallback_location: job_path(@job, search_profile_id: @search_profile.id), alert: "Link de candidatura indisponivel."
      return
    end

    job_match = @job.job_matches.find_by!(search_profile: @search_profile)
    job_match.update!(user_state: :seen) if job_match.user_state_new_match?
  end

  def mark
    state = params.require(:user_state)

    unless JobMatch.user_states.key?(state)
      redirect_back fallback_location: jobs_path, alert: "Status invalido."
      return
    end

    @job.job_matches.find_by!(search_profile: @search_profile).update!(user_state: state)
    redirect_back fallback_location: job_path(@job, search_profile_id: @search_profile.id), notice: job_state_notice(state)
  end

  private
    def ensure_search_profile!
      return if current_user.search_profiles.exists?

      redirect_to new_search_profile_path(onboarding: 1), alert: "Crie seu primeiro perfil para iniciar o radar."
    end

    def filter_params
      params.permit(:q, :stack, :source, :contract_type, :match_strength, :user_state, :title_language, :lifecycle_state, :recency, :sort)
    end

    def set_search_profile
      @search_profile = selected_search_profile
      session[:search_profile_id] = @search_profile.id
    end

    def selected_search_profile
      requested_id = params[:search_profile_id].presence || session[:search_profile_id]
      current_user.search_profiles.find_by(id: requested_id) || current_user.search_profiles.ordered.first
    end

    def set_job
      @job = Job.includes(:job_source).find(params[:id])
    end

    def job_state_notice(state)
      case state
      when "seen"
        "Vaga marcada como vista."
      when "applied"
        "Vaga marcada como aplicada."
      when "ignored"
        "Vaga marcada como ignorada."
      else
        "Status atualizado."
      end
    end
end
