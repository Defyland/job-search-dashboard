class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Tente novamente em alguns minutos." }

  def new
    return redirect_to root_path if existing_session?

    @user = User.new
  end

  def create
    return redirect_to root_path if existing_session?

    @user = User.new(registration_params)

    if @user.save
      start_new_session_for @user
      redirect_to new_search_profile_path(onboarding: 1), notice: "Conta criada. Configure seu perfil para comecar."
    else
      flash.now[:alert] = "Nao foi possivel criar sua conta."
      render :new, status: :unprocessable_entity
    end
  end

  private
    def existing_session?
      find_session_by_cookie.present?
    end

    def registration_params
      params.expect(user: [ :email_address, :password, :password_confirmation ])
    end
end
