class PagesController < ApplicationController
  allow_unauthenticated_access only: :home
  layout false

  # Public marketing landing at "/". Authenticated operators skip it and go straight to the radar.
  def home
    return redirect_to jobs_path if authenticated?

    @source_count = JobSources::Catalog.defaults.size
    @source_names = JobSources::Catalog.defaults.map { |source| source.fetch(:name) }
  end
end
