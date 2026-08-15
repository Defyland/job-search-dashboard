module Authentication
  extend ActiveSupport::Concern

  SESSION_TTL_DAYS = Integer(ENV.fetch("SESSION_TTL_DAYS", "30"))

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= begin
        session = find_session_by_cookie
        touch_session_usage(session) if session
        session
      end
    end

    def find_session_by_cookie
      session_id = cookies.signed[:session_id]
      return unless session_id

      session = Session.find_by(id: session_id)
      return unless session

      if session.expires_at.nil? || session.expires_at > Time.current
        session
      else
        session.destroy
        nil
      end
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.fullpath
      redirect_to new_session_path
    end

    def after_authentication_url
      path = session.delete(:return_to_after_authenticating)
      path.to_s.start_with?("/") && !path.to_s.start_with?("//") ? path : root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(
        user_agent: request.user_agent,
        ip_address: request.remote_ip,
        expires_at: SESSION_TTL_DAYS.days.from_now
      ).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    # Best-effort usage tracking: only writes when stale to avoid a DB write
    # on every request. Never raises, so a tracking failure can't break auth.
    def touch_session_usage(session)
      return if session.last_used_at.present? && session.last_used_at > 1.minute.ago

      session.update_columns(last_used_at: Time.current)
    rescue StandardError
      nil
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
