class SearchProfilesController < ApplicationController
  before_action :set_search_profile, only: %i[edit update destroy]
  before_action :build_new_search_profile, only: %i[new create]
  before_action :set_onboarding_mode, only: %i[new create]
  before_action :set_intent_compiler_availability, only: %i[new edit create update]

  def index
    @search_profiles = current_user.search_profiles.ordered
  end

  def new
    hydrate_form_state(@search_profile)
  end

  def create
    return persist_onboarding_profile(@search_profile) if onboarding_mode?
    return render_compiled_preview(@search_profile) if preview_compile_requested?

    persist_profile(
      @search_profile,
      template: :new,
      success_path: ->(profile) { jobs_path(search_profile_id: profile.id) },
      success_notice: "Perfil criado. Busca inicial enfileirada.",
      after_save: ->(profile) { request_profile_sync!(profile, prune_stale: false) }
    )
  end

  def edit
    hydrate_form_state(@search_profile)
  end

  def update
    return render_compiled_preview(@search_profile) if preview_compile_requested?

    persist_profile(
      @search_profile,
      template: :edit,
      success_path: ->(_profile) { search_profiles_path },
      success_notice: "Perfil atualizado. Busca reenfileirada.",
      after_save: ->(profile) { request_profile_sync!(profile, prune_stale: true) }
    )
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
    def build_new_search_profile
      @search_profile = current_user.search_profiles.new(SearchProfile.default_attributes)
    end

    def set_search_profile
      @search_profile = current_user.search_profiles.find(params[:id])
    end

    def set_intent_compiler_availability
      @intent_compiler_available = SearchProfiles::CompilerClient.available?
      @intent_compiler_setup_hint = SearchProfiles::CompilerClient.setup_hint
    end

    def set_onboarding_mode
      @onboarding_mode = onboarding_mode?
    end

    def intent_compiler
      @intent_compiler ||= SearchProfiles::IntentCompiler.new
    end

    def heuristic_intent_compiler
      @heuristic_intent_compiler ||= SearchProfiles::HeuristicIntentCompiler.new
    end

    def compiled_payload_token
      @compiled_payload_token ||= SearchProfiles::CompiledPayloadToken.new
    end

    def persist_onboarding_profile(search_profile)
      form_attributes = profile_form_params.to_h
      form_state = SearchProfiles::FormState.new(search_profile:, submitted_attributes: form_attributes)
      simple_input = form_state.simple_input

      search_profile.assign_attributes(
        SearchProfiles::ProfileBuilder.from_compiled(
          simple_input:,
          compiled_payload: compile_with_fallback(simple_input),
          active: form_state.active_default
        )
      )

      if search_profile.valid?
        SearchProfile.transaction do
          search_profile.save!
          request_profile_sync!(search_profile, prune_stale: false)
        end
        redirect_to jobs_path(search_profile_id: search_profile.id), notice: "Perfil criado. Busca inicial enfileirada."
      else
        hydrate_form_state(search_profile, form_attributes)
        render :new, status: :unprocessable_entity
      end
    rescue SearchProfiles::IntentCompiler::Error => error
      search_profile.errors.add(:base, error.message)
      hydrate_form_state(search_profile, form_attributes)
      render :new, status: :unprocessable_entity
    rescue SearchProfiles::SyncRequest::Error => error
      search_profile.errors.add(:base, error.message)
      hydrate_form_state(search_profile, form_attributes)
      render :new, status: :service_unavailable
    end

    def persist_profile(search_profile, template:, success_path:, success_notice:, after_save: nil)
      form_attributes = profile_form_params.to_h
      search_profile.assign_attributes(profile_attributes_for_save(search_profile, form_attributes))

      if search_profile.valid?
        SearchProfile.transaction do
          search_profile.save!
          after_save&.call(search_profile)
        end
        redirect_to success_path.call(search_profile), notice: success_notice
      else
        restore_compiled_preview(form_attributes["compiled_profile_payload"])
        hydrate_form_state(search_profile, form_attributes)
        render template, status: :unprocessable_entity
      end
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      search_profile.errors.add(:base, "As variacoes geradas expiraram ou foram alteradas. Gere novamente antes de salvar.")
      hydrate_form_state(search_profile, form_attributes)
      render template, status: :unprocessable_entity
    rescue SearchProfiles::IntentCompiler::Error => error
      search_profile.errors.add(:base, error.message)
      restore_compiled_preview(form_attributes["compiled_profile_payload"])
      hydrate_form_state(search_profile, form_attributes)
      render template, status: :unprocessable_entity
    rescue SearchProfiles::SyncRequest::Error => error
      search_profile.errors.add(:base, error.message)
      restore_compiled_preview(form_attributes["compiled_profile_payload"])
      hydrate_form_state(search_profile, form_attributes)
      render template, status: :service_unavailable
    end

    def profile_attributes_for_save(search_profile, form_attributes)
      form_state = SearchProfiles::FormState.new(search_profile:, submitted_attributes: form_attributes)

      if form_attributes["compiled_profile_payload"].present?
        simple_input = form_state.simple_input
        compiled_payload = compiled_payload_token.verify_for!(form_attributes["compiled_profile_payload"], simple_input:)

        SearchProfiles::ProfileBuilder.from_compiled(
          simple_input:,
          compiled_payload:,
          manual_overrides: form_state.manual_overrides,
          active: form_state.active_default
        )
      else
        SearchProfiles::ProfileBuilder.from_manual(
          form_attributes:,
          existing_settings: search_profile.settings,
          active_default: form_state.active_default
        )
      end
    end

    def hydrate_form_state(search_profile, submitted_attributes = {})
      form_state = SearchProfiles::FormState.new(
        search_profile:,
        submitted_attributes:,
        compiled_preview: @compiled_preview,
        compiled_profile_payload: @compiled_profile_payload
      )
      @simple_profile_input = form_state.hydrated_simple_input
      @compiled_profile_payload = form_state.compiled_profile_payload
      @advanced_open ||= form_state.advanced_open?
    end

    def restore_compiled_preview(token)
      return if token.blank?

      compiled_payload = compiled_payload_token.verify(token)
      @compiled_preview = compiled_payload
      @compiled_profile_payload = token
      @advanced_open = true
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def compiler_input_from(simple_input)
      simple_input.slice(
        "technology_intent",
        "seniority_preset",
        "language_scope",
        "required_remote",
        "region_scope",
        "include_women_only"
      ).symbolize_keys
    end

    def compile_with_fallback(simple_input)
      return heuristic_intent_compiler.call(**compiler_input_from(simple_input)) unless @intent_compiler_available

      intent_compiler.call(**compiler_input_from(simple_input))
    rescue SearchProfiles::CompilerClient::ConfigurationError, SearchProfiles::IntentCompiler::Error
      heuristic_intent_compiler.call(**compiler_input_from(simple_input))
    end

    def preview_compile_requested?
      params[:preview_compile] == "1"
    end

    def onboarding_mode?
      params[:onboarding] == "1"
    end

    def render_compiled_preview(search_profile)
      form_attributes = profile_form_params.to_h
      form_state = SearchProfiles::FormState.new(search_profile:, submitted_attributes: form_attributes)
      simple_input = form_state.simple_input
      compiled_payload = intent_compiler.call(**compiler_input_from(simple_input))
      compiled_payload["request_fingerprint"] = SearchProfiles::ProfileBuilder.intent_fingerprint(simple_input)

      @compiled_preview = compiled_payload
      @compiled_profile_payload = compiled_payload_token.sign(compiled_payload)
      search_profile.assign_attributes(
        SearchProfiles::ProfileBuilder.from_compiled(
          simple_input: simple_input,
          compiled_payload: compiled_payload,
          active: form_state.active_default
        )
      )

      hydrate_form_state(search_profile, form_attributes)
      @advanced_open = true
      render search_profile.persisted? ? :edit : :new
    rescue SearchProfiles::IntentCompiler::Error => error
      search_profile.assign_attributes(
        SearchProfiles::ProfileBuilder.from_manual(
          form_attributes: form_attributes,
          existing_settings: search_profile.settings,
          active_default: form_state.active_default
        )
      )
      search_profile.errors.add(:base, error.message)
      hydrate_form_state(search_profile, form_attributes)
      @advanced_open = true
      render search_profile.persisted? ? :edit : :new, status: :unprocessable_entity
    end

    def profile_form_params
      params.fetch(:search_profile, ActionController::Parameters.new).permit(
        :name,
        :id,
        :active,
        :required_remote,
        :include_women_only,
        :language_scope,
        :technology_intent,
        :seniority_preset,
        :region_scope,
        :scan_window_days,
        :compiled_profile_payload,
        :target_stacks_text,
        :target_titles_text,
        :seniority_terms_text,
        :location_terms_text,
        :negative_terms_text,
        stack_presets: []
      )
    end

    def request_profile_sync!(search_profile, prune_stale:)
      SearchProfiles::SyncRequest.new(search_profile:, prune_stale:).call
    end
end
