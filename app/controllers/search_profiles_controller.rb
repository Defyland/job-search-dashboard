class SearchProfilesController < ApplicationController
  before_action :set_search_profile, only: %i[edit update destroy]

  def index
    @search_profiles = current_user.search_profiles.ordered
  end

  def new
    @search_profile = current_user.search_profiles.new(SearchProfile.default_attributes)
  end

  def create
    @search_profile = current_user.search_profiles.new(search_profile_params)

    if @search_profile.save
      redirect_to jobs_path(search_profile_id: @search_profile.id), notice: "Perfil criado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @search_profile.update(search_profile_params)
      redirect_to search_profiles_path, notice: "Perfil atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if current_user.search_profiles.where.not(id: @search_profile.id).exists?
      @search_profile.destroy!
      redirect_to search_profiles_path, notice: "Perfil removido."
    else
      redirect_to search_profiles_path, alert: "Mantenha ao menos um perfil ativo para o radar."
    end
  end

  private
    def set_search_profile
      @search_profile = current_user.search_profiles.find(params[:id])
    end

    def search_profile_params
      params.require(:search_profile).permit(
        :name,
        :active,
        :required_remote,
        :include_women_only,
        :scan_window_days,
        :target_stacks_text,
        :target_titles_text,
        :seniority_terms_text,
        :location_terms_text,
        :negative_terms_text
      )
    end
end
