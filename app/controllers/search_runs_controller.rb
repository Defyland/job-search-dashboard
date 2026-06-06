class SearchRunsController < ApplicationController
  def index
    @search_runs = SearchRun.order(started_at: :desc).limit(50)
  end

  def show
    @search_run = SearchRun.find(params[:id])
    @items = @search_run.search_run_items.includes(:job).order(created_at: :desc)
  end
end
