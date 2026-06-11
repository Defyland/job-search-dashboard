class PagesController < ApplicationController
  allow_unauthenticated_access only: :home
  layout false

  # Public marketing landing at "/". Authenticated operators skip it and go straight to the radar.
  def home
    redirect_to jobs_path if authenticated?
  end
end
