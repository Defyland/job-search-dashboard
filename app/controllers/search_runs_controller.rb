class SearchRunsController < ApplicationController
  def index
    @search_runs = SearchRun.order(started_at: :desc).limit(50)
  end

  def create
    window_days = params.fetch(:window_days, 20).to_i.clamp(1, 30)
    DiscoverJobsRunJob.perform_later(window_days:, trigger_source: :manual)

    redirect_to search_runs_path, notice: "Backfill Rails enfileirado para #{window_days} dias."
  end

  def show
    @search_run = SearchRun.find(params[:id])
    @items = @search_run.search_run_items.includes(:job).order(created_at: :desc)
    @source_scans = @search_run.source_scans.includes(:job_source).order(created_at: :asc)
  end
end
