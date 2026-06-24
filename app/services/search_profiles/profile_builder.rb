require "digest"
require "json"

module SearchProfiles
  class ProfileBuilder
    BOOLEAN = ActiveModel::Type::Boolean.new

    def self.from_compiled(simple_input:, compiled_payload:, manual_overrides: {}, active: true)
      language_scope = SearchProfiles::Vocabulary.normalize_language_scope(simple_input["language_scope"])
      required_remote = BOOLEAN.cast(simple_input["required_remote"])
      region_scope = SearchProfiles::Vocabulary.normalize_region_scope(simple_input["region_scope"])
      seniority_preset = SearchProfiles::Vocabulary.normalize_seniority_preset(simple_input["seniority_preset"])
      compiled_payload = compiled_payload.deep_stringify_keys

      attributes = {
        name: simple_input["name"].presence || compiled_payload["profile_name_suggestion"],
        active: BOOLEAN.cast(active),
        required_remote: required_remote,
        include_women_only: BOOLEAN.cast(simple_input["include_women_only"]),
        language_scope: language_scope,
        scan_window_days: SearchProfiles::Vocabulary.normalize_scan_window_days(simple_input["scan_window_days"]),
        target_stacks: SearchProfiles::Vocabulary.normalize_list(compiled_payload["canonical_stacks"]),
        target_titles: SearchProfiles::Vocabulary.normalize_list(
          generated_titles_for(compiled_payload, language_scope) + SearchProfiles::Vocabulary.role_titles_for(language_scope)
        ),
        seniority_terms: SearchProfiles::Vocabulary.normalize_list(SearchProfiles::Vocabulary::SENIORITY_PRESETS.fetch(seniority_preset)),
        location_terms: SearchProfiles::Vocabulary.location_terms_for(required_remote:, region_scope:),
        negative_terms: SearchProfiles::Vocabulary.normalize_list(SearchProfiles::Vocabulary::DEFAULT_NEGATIVE_TERMS),
        settings: compiled_settings(simple_input:, compiled_payload:, language_scope:, required_remote:, region_scope:, seniority_preset:)
      }

      apply_manual_overrides(attributes, manual_overrides)
    end

    def self.from_manual(form_attributes:, existing_settings: {}, active_default: true)
      form_attributes = form_attributes.deep_stringify_keys

      attributes = {
        name: form_attributes["name"],
        active: boolean_or_default(form_attributes["active"], active_default),
        required_remote: boolean_or_default(form_attributes["required_remote"], true),
        include_women_only: boolean_or_default(form_attributes["include_women_only"], false),
        language_scope: SearchProfiles::Vocabulary.normalize_language_scope(form_attributes["language_scope"]),
        target_stacks: SearchProfiles::Vocabulary.normalize_list(form_attributes["target_stacks_text"]),
        target_titles: SearchProfiles::Vocabulary.normalize_list(form_attributes["target_titles_text"]),
        seniority_terms: SearchProfiles::Vocabulary.normalize_list(form_attributes["seniority_terms_text"]),
        location_terms: SearchProfiles::Vocabulary.normalize_list(form_attributes["location_terms_text"]),
        negative_terms: SearchProfiles::Vocabulary.normalize_list(form_attributes["negative_terms_text"]),
        settings: existing_settings.presence || {}
      }
      attributes[:scan_window_days] = SearchProfiles::Vocabulary.normalize_scan_window_days(form_attributes["scan_window_days"]) if form_attributes.key?("scan_window_days")
      attributes
    end

    def self.intent_fingerprint(simple_input)
      normalized_input = simple_input.deep_stringify_keys.slice(
        "technology_intent",
        "seniority_preset",
        "language_scope",
        "required_remote",
        "region_scope",
        "include_women_only"
      ).transform_values { |value| value.is_a?(String) ? value.to_s.squish.downcase : BOOLEAN.cast(value) }

      Digest::SHA256.hexdigest(JSON.generate(normalized_input))
    end

    def self.generated_titles_for(compiled_payload, language_scope)
      case language_scope
      when "portuguese"
        compiled_payload["title_variants_pt"]
      when "english"
        compiled_payload["title_variants_en"]
      else
        Array(compiled_payload["title_variants_pt"]) + Array(compiled_payload["title_variants_en"])
      end
    end

    def self.stack_alias_map(compiled_payload)
      Array(compiled_payload["stack_aliases"]).each_with_object({}) do |entry, result|
        canonical_stack = entry["canonical_stack"].to_s.downcase.squish
        next if canonical_stack.blank?

        result[canonical_stack] = SearchProfiles::Vocabulary.normalize_list(entry["aliases"])
      end
    end

    def self.compiled_settings(simple_input:, compiled_payload:, language_scope:, required_remote:, region_scope:, seniority_preset:)
      {
        "intent" => {
          "technology_intent" => simple_input["technology_intent"].to_s.squish,
          "seniority_preset" => seniority_preset,
          "language_scope" => language_scope,
          "required_remote" => required_remote,
          "region_scope" => region_scope,
          "include_women_only" => BOOLEAN.cast(simple_input["include_women_only"]),
          "manual_name_override" => simple_input["name"].present?
        },
        "compiler" => {
          "provider" => compiled_payload["provider"].presence || SearchProfiles::CompilerClient::PROVIDER,
          "model" => compiled_payload["model"].presence || SearchProfiles::CompilerClient::DEFAULT_MODEL,
          "compiled_at" => Time.current.iso8601,
          "profile_name_suggestion" => compiled_payload["profile_name_suggestion"].to_s.squish,
          "stack_aliases" => stack_alias_map(compiled_payload),
          "generated_titles" => {
            "pt" => SearchProfiles::Vocabulary.normalize_list(compiled_payload["title_variants_pt"]),
            "en" => SearchProfiles::Vocabulary.normalize_list(compiled_payload["title_variants_en"])
          },
          "request_fingerprint" => compiled_payload["request_fingerprint"]
        }
      }
    end
    private_class_method :compiled_settings

    def self.apply_manual_overrides(attributes, manual_overrides)
      manual_overrides = manual_overrides.deep_stringify_keys

      SearchProfiles::Vocabulary::MANUAL_OVERRIDE_FIELDS.each do |field, param_key|
        next if manual_overrides[param_key].blank?

        attributes[field] = SearchProfiles::Vocabulary.normalize_list(manual_overrides[param_key])
      end

      attributes
    end
    private_class_method :apply_manual_overrides

    def self.boolean_or_default(value, default)
      return default if value.nil?

      BOOLEAN.cast(value)
    end
    private_class_method :boolean_or_default
  end
end
