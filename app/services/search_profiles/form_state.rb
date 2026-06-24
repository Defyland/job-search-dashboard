module SearchProfiles
  class FormState
    def initialize(search_profile:, submitted_attributes: {}, compiled_preview: nil, compiled_profile_payload: nil)
      @search_profile = search_profile
      @submitted_attributes = submitted_attributes.deep_stringify_keys
      @compiled_preview = compiled_preview
      @compiled_profile_payload = compiled_profile_payload.presence || @submitted_attributes["compiled_profile_payload"]
    end

    def simple_input
      {
        "name" => submitted_name,
        "technology_intent" => submitted_technology_intent,
        "stack_presets" => selected_stack_presets,
        "seniority_preset" => @submitted_attributes["seniority_preset"].presence || SearchProfiles::Vocabulary::DEFAULT_SENIORITY_PRESET,
        "language_scope" => @submitted_attributes["language_scope"].presence || SearchProfiles::Vocabulary::DEFAULT_LANGUAGE_SCOPE,
        "required_remote" => @submitted_attributes.key?("required_remote") ? @submitted_attributes["required_remote"] : true,
        "region_scope" => @submitted_attributes["region_scope"].presence || SearchProfiles::Vocabulary::DEFAULT_REGION_SCOPE,
        "include_women_only" => @submitted_attributes.key?("include_women_only") ? @submitted_attributes["include_women_only"] : false,
        "scan_window_days" => submitted_scan_window_days
      }
    end

    def hydrated_simple_input
      @search_profile.simple_form_state.merge(simple_input_overrides)
    end

    def manual_overrides
      @submitted_attributes.slice(*SearchProfiles::Vocabulary::MANUAL_OVERRIDE_FIELDS.values)
    end

    def active_default
      if @search_profile.persisted?
        @submitted_attributes.key?("active") ? @submitted_attributes["active"] : @search_profile.active
      else
        true
      end
    end

    def compiled_profile_payload
      @compiled_profile_payload
    end

    def advanced_open?
      @search_profile.errors.any? || @compiled_preview.present? || (@search_profile.persisted? && !@search_profile.intent_backed?)
    end

    private
      def simple_input_overrides
        {}.tap do |overrides|
          overrides["name"] = submitted_name if name_override?
          overrides["technology_intent"] = submitted_technology_intent if technology_intent_override?
          overrides["stack_presets"] = selected_stack_presets if stack_presets_override?
          overrides["seniority_preset"] = @submitted_attributes["seniority_preset"].presence || SearchProfiles::Vocabulary::DEFAULT_SENIORITY_PRESET if @submitted_attributes.key?("seniority_preset")
          overrides["language_scope"] = @submitted_attributes["language_scope"].presence || SearchProfiles::Vocabulary::DEFAULT_LANGUAGE_SCOPE if @submitted_attributes.key?("language_scope")
          overrides["required_remote"] = @submitted_attributes["required_remote"] if @submitted_attributes.key?("required_remote")
          overrides["region_scope"] = @submitted_attributes["region_scope"].presence || SearchProfiles::Vocabulary::DEFAULT_REGION_SCOPE if @submitted_attributes.key?("region_scope")
          overrides["include_women_only"] = @submitted_attributes["include_women_only"] if @submitted_attributes.key?("include_women_only")
          overrides["scan_window_days"] = SearchProfiles::Vocabulary.normalize_scan_window_days(@submitted_attributes["scan_window_days"]) if @submitted_attributes.key?("scan_window_days")
        end
      end

      def submitted_name
        return "" unless name_override?

        @submitted_attributes["name"].to_s
      end

      def submitted_scan_window_days
        SearchProfiles::Vocabulary.normalize_scan_window_days(
          @submitted_attributes.fetch("scan_window_days", @search_profile.scan_window_days)
        )
      end

      def name_override?
        return false unless @submitted_attributes.key?("name")
        return true if @search_profile.persisted?

        @submitted_attributes["name"].to_s != SearchProfile.default_attributes.fetch(:name)
      end

      def submitted_technology_intent
        SearchProfiles::Vocabulary.normalize_list(selected_stack_presets + [ submitted_technology_intent_text ]).join(", ")
      end

      def submitted_technology_intent_text
        @submitted_attributes["technology_intent"].to_s
      end

      def selected_stack_presets
        presets = Array(@submitted_attributes["stack_presets"])
        allowed_preset_values = SearchProfiles::Vocabulary::ONBOARDING_STACK_PRESETS.map { |preset| preset.fetch("value") }

        SearchProfiles::Vocabulary.normalize_list(presets).select do |preset|
          allowed_preset_values.include?(preset)
        end
      end

      def technology_intent_override?
        @submitted_attributes.key?("technology_intent") || stack_presets_override?
      end

      def stack_presets_override?
        @submitted_attributes.key?("stack_presets")
      end
  end
end
