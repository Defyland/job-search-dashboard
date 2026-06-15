class PagesController < ApplicationController
  allow_unauthenticated_access only: :home
  layout false

  # Public marketing landing at "/". Authenticated operators skip it and go straight to the radar.
  def home
    if authenticated?
      return redirect_to new_search_profile_path(onboarding: 1) unless current_user.search_profiles.exists?
      return redirect_to jobs_path
    end

    @source_count = JobSources::Catalog.defaults.size
    @source_names = JobSources::Catalog.defaults.map { |source| source.fetch(:name) }
    @waitlist_email = flash[:waitlist_email].to_s
  end
end
