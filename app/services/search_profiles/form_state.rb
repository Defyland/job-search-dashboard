module SearchProfiles
  class FormState
    MANUAL_OVERRIDE_FIELDS = %w[
      target_stacks_text
      target_titles_text
      seniority_terms_text
      location_terms_text
      negative_terms_text
    ].freeze

    def initialize(search_profile:, submitted_attributes: {}, compiled_preview: nil, compiled_profile_payload: nil)
      @search_profile = search_profile
      @submitted_attributes = submitted_attributes.deep_stringify_keys
      @compiled_preview = compiled_preview
      @compiled_profile_payload = compiled_profile_payload.presence || @submitted_attributes["compiled_profile_payload"]
    end

    def simple_input
      {
        "name" => submitted_name,
        "technology_intent" => @submitted_attributes["technology_intent"].to_s,
        "seniority_preset" => @submitted_attributes["seniority_preset"].presence || "senior",
        "language_scope" => @submitted_attributes["language_scope"].presence || "both",
        "required_remote" => @submitted_attributes.key?("required_remote") ? @submitted_attributes["required_remote"] : true,
        "region_scope" => @submitted_attributes["region_scope"].presence || "brazil_latam",
        "include_women_only" => @submitted_attributes.key?("include_women_only") ? @submitted_attributes["include_women_only"] : false
      }
    end

    def hydrated_simple_input
      @search_profile.simple_form_state.merge(simple_input_overrides)
    end

    def manual_overrides
      @submitted_attributes.slice(*MANUAL_OVERRIDE_FIELDS)
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
          overrides["technology_intent"] = @submitted_attributes["technology_intent"].to_s if @submitted_attributes.key?("technology_intent")
          overrides["seniority_preset"] = @submitted_attributes["seniority_preset"].presence || "senior" if @submitted_attributes.key?("seniority_preset")
          overrides["language_scope"] = @submitted_attributes["language_scope"].presence || "both" if @submitted_attributes.key?("language_scope")
          overrides["required_remote"] = @submitted_attributes["required_remote"] if @submitted_attributes.key?("required_remote")
          overrides["region_scope"] = @submitted_attributes["region_scope"].presence || "brazil_latam" if @submitted_attributes.key?("region_scope")
          overrides["include_women_only"] = @submitted_attributes["include_women_only"] if @submitted_attributes.key?("include_women_only")
        end
      end

      def submitted_name
        return "" unless name_override?

        @submitted_attributes["name"].to_s
      end

      def name_override?
        return false unless @submitted_attributes.key?("name")
        return true if @search_profile.persisted?

        @submitted_attributes["name"].to_s != SearchProfile.default_attributes.fetch(:name)
      end
  end
end
