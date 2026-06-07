class SearchProfilesController < ApplicationController
  before_action :set_search_profile, only: %i[edit update destroy]
  before_action :build_new_search_profile, only: %i[new create]
  before_action :set_intent_compiler_availability, only: %i[new edit create update]

  def index
    @search_profiles = current_user.search_profiles.ordered
  end

  def new
    hydrate_form_state(@search_profile)
  end

  def create
    return render_compiled_preview(@search_profile) if preview_compile_requested?

    persist_profile(
      @search_profile,
      template: :new,
      success_path: ->(profile) { jobs_path(search_profile_id: profile.id) },
      success_notice: "Perfil criado. Busca inicial iniciada.",
      after_save: ->(profile) { bootstrap_profile!(profile) }
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
      success_notice: "Perfil atualizado. Busca atualizada.",
      after_save: ->(profile) { refresh_profile!(profile) }
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

    def intent_compiler
      @intent_compiler ||= SearchProfiles::IntentCompiler.new
    end

    def persist_profile(search_profile, template:, success_path:, success_notice:, after_save: nil)
      form_attributes = profile_form_params.to_h
      search_profile.assign_attributes(profile_attributes_for_save(search_profile, form_attributes))

      if search_profile.save
        after_save&.call(search_profile)
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
    end

    def profile_attributes_for_save(search_profile, form_attributes)
      if form_attributes["compiled_profile_payload"].present?
        compiled_payload = verified_compiled_payload(form_attributes["compiled_profile_payload"])
        simple_input = simple_input_from(form_attributes)
        expected_fingerprint = SearchProfiles::ProfileBuilder.intent_fingerprint(simple_input)

        if compiled_payload["request_fingerprint"] != expected_fingerprint
          raise SearchProfiles::IntentCompiler::Error, "As variacoes geradas nao correspondem mais aos filtros atuais. Gere novamente antes de salvar."
        end

        SearchProfiles::ProfileBuilder.from_compiled(
          simple_input:,
          compiled_payload:,
          manual_overrides: manual_override_params(form_attributes),
          active: active_default_for(search_profile, form_attributes)
        )
      else
        SearchProfiles::ProfileBuilder.from_manual(
          form_attributes:,
          existing_settings: search_profile.settings,
          active_default: active_default_for(search_profile, form_attributes)
        )
      end
    end

    def hydrate_form_state(search_profile, submitted_attributes = {})
      @simple_profile_input = search_profile.simple_form_state.merge(simple_input_from(submitted_attributes))
      @compiled_profile_payload ||= submitted_attributes["compiled_profile_payload"]
      @advanced_open ||= search_profile.errors.any? || @compiled_preview.present? || (search_profile.persisted? && !search_profile.intent_backed?)
    end

    def restore_compiled_preview(token)
      return if token.blank?

      compiled_payload = verified_compiled_payload(token)
      @compiled_preview = compiled_payload
      @compiled_profile_payload = token
      @advanced_open = true
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def sign_compiled_payload(compiled_payload)
      profile_compile_verifier.generate(JSON.generate(compiled_payload))
    end

    def verified_compiled_payload(token)
      JSON.parse(profile_compile_verifier.verify(token))
    end

    def profile_compile_verifier
      @profile_compile_verifier ||= Rails.application.message_verifier("search-profile-compile")
    end

    def active_default_for(search_profile, form_attributes)
      if search_profile.persisted?
        form_attributes.key?("active") ? form_attributes["active"] : search_profile.active
      else
        true
      end
    end

    def simple_input_from(attributes)
      attributes = attributes.deep_stringify_keys

      {
        "name" => attributes["name"].to_s,
        "technology_intent" => attributes["technology_intent"].to_s,
        "seniority_preset" => attributes["seniority_preset"].presence || "senior",
        "language_scope" => attributes["language_scope"].presence || "both",
        "required_remote" => attributes.key?("required_remote") ? attributes["required_remote"] : true,
        "region_scope" => attributes["region_scope"].presence || "brazil_latam",
        "include_women_only" => attributes.key?("include_women_only") ? attributes["include_women_only"] : false
      }
    end

    def manual_override_params(attributes)
      attributes.deep_stringify_keys.slice(
        "target_stacks_text",
        "target_titles_text",
        "seniority_terms_text",
        "location_terms_text",
        "negative_terms_text"
      )
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

    def preview_compile_requested?
      params[:preview_compile] == "1"
    end

    def render_compiled_preview(search_profile)
      form_attributes = profile_form_params.to_h
      simple_input = simple_input_from(form_attributes)
      compiled_payload = intent_compiler.call(**compiler_input_from(simple_input))
      compiled_payload["request_fingerprint"] = SearchProfiles::ProfileBuilder.intent_fingerprint(simple_input)

      @compiled_preview = compiled_payload
      @compiled_profile_payload = sign_compiled_payload(compiled_payload)
      search_profile.assign_attributes(
        SearchProfiles::ProfileBuilder.from_compiled(
          simple_input: simple_input,
          compiled_payload: compiled_payload,
          active: active_default_for(search_profile, form_attributes)
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
          active_default: active_default_for(search_profile, form_attributes)
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
        :compiled_profile_payload,
        :target_stacks_text,
        :target_titles_text,
        :seniority_terms_text,
        :location_terms_text,
        :negative_terms_text
      )
    end

    def bootstrap_profile!(search_profile)
      SearchProfiles::Bootstrapper.new(search_profile:).call
      DiscoverJobsRunJob.perform_later(window_days: search_profile.scan_window_days, trigger_source: :manual)
    end

    def refresh_profile!(search_profile)
      SearchProfiles::Bootstrapper.new(search_profile:, prune_stale: true).call
      DiscoverJobsRunJob.perform_later(window_days: search_profile.scan_window_days, trigger_source: :manual)
    end
end
