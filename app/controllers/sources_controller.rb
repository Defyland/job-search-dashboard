class SourcesController < ApplicationController
  def index
    @sources = JobSource.left_outer_joins(:jobs)
                        .select("job_sources.*, COUNT(jobs.id) AS jobs_count")
                        .group("job_sources.id")
                        .order(priority: :asc, name: :asc)
  end
end
