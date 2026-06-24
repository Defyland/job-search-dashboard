class SearchRunsController < ApplicationController
  def index
    @search_runs = SearchRun.order(started_at: :desc).limit(50)
    @source_options = JobSource.backfillable.order(priority: :asc, name: :asc)
  end

  def create
    window_days = params.fetch(:window_days, SearchProfiles::Vocabulary::DEFAULT_SCAN_WINDOW_DAYS).to_i.clamp(
      1,
      SearchProfiles::Vocabulary::MAX_SCAN_WINDOW_DAYS
    )
    source_slug = params[:source_slug].presence

    if source_slug.present?
      source = JobSource.backfillable.find_by(slug: source_slug)

      unless source
        redirect_to search_runs_path, alert: "Fonte invalida para backfill."
        return
      end
    end

    DiscoverJobsRunJob.perform_later(window_days:, trigger_source: :manual, source_slug:)

    notice = if source_slug.present?
      "Backfill Rails da fonte #{source.name} enfileirado para #{window_days} dias."
    else
      "Backfill Rails enfileirado para #{window_days} dias."
    end

    redirect_to search_runs_path, notice:
  end

  def show
    @search_run = SearchRun.find(params[:id])
    @items = @search_run.search_run_items.includes(:job).order(created_at: :desc)
    @source_scans = @search_run.source_scans.includes(:job_source).order(created_at: :asc)
  end
end
