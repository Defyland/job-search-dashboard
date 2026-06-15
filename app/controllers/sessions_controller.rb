class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Tente novamente em alguns minutos." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to post_login_destination_for(user)
    else
      redirect_to new_session_path, alert: "Email ou senha invalidos."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: "Sessao encerrada.", status: :see_other
  end

  private
    def post_login_destination_for(user)
      return new_search_profile_path(onboarding: 1) unless user.search_profiles.exists?

      after_authentication_url
    end
end
