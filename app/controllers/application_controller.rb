class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :registration_open?, :admin?

  private
    def current_user
      Current.user
    end

    def registration_open?
      Rails.configuration.x.allow_public_registration
    end

    def admin?
      current_user&.admin?
    end

    def require_admin
      return if admin?

      render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
    end
end
