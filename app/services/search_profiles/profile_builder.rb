require "digest"
require "json"

module SearchProfiles
  class ProfileBuilder
    BOOLEAN = ActiveModel::Type::Boolean.new

    SENIORITY_PRESETS = {
      "senior" => [ "senior", "sênior", "sr", "staff" ],
      "staff" => [ "staff", "senior staff", "sr staff" ],
      "principal" => [ "principal", "staff", "senior staff" ]
    }.freeze

    REGION_TERMS = {
      "brazil_latam" => [ "brasil", "brazil", "latam" ],
      "brazil" => [ "brasil", "brazil" ],
      "latam" => [ "latam" ],
      "global_remote" => [ "worldwide", "global", "anywhere" ]
    }.freeze

    ROLE_TITLES_BY_LANGUAGE = {
      "both" => SearchProfile::DEFAULT_TARGET_TITLES,
      "portuguese" => [ "engenheiro de software", "desenvolvedor", "frontend", "backend", "fullstack" ],
      "english" => [ "software engineer", "developer", "frontend", "backend", "fullstack" ]
    }.freeze

    MANUAL_OVERRIDE_FIELDS = {
      target_stacks: "target_stacks_text",
      target_titles: "target_titles_text",
      seniority_terms: "seniority_terms_text",
      location_terms: "location_terms_text",
      negative_terms: "negative_terms_text"
    }.freeze

    def self.from_compiled(simple_input:, compiled_payload:, manual_overrides: {}, active: true)
      language_scope = normalize_language_scope(simple_input["language_scope"])
      required_remote = BOOLEAN.cast(simple_input["required_remote"])
      region_scope = normalize_region_scope(simple_input["region_scope"])
      seniority_preset = normalize_seniority_preset(simple_input["seniority_preset"])
      compiled_payload = compiled_payload.deep_stringify_keys

      attributes = {
        name: simple_input["name"].presence || compiled_payload["profile_name_suggestion"],
        active: BOOLEAN.cast(active),
        required_remote: required_remote,
        include_women_only: BOOLEAN.cast(simple_input["include_women_only"]),
        language_scope: language_scope,
        target_stacks: normalize_list(compiled_payload["canonical_stacks"]),
        target_titles: normalize_list(
          generated_titles_for(compiled_payload, language_scope) + role_titles_for(language_scope)
        ),
        seniority_terms: normalize_list(SENIORITY_PRESETS.fetch(seniority_preset)),
        location_terms: location_terms_for(required_remote:, region_scope:),
        negative_terms: normalize_list(SearchProfile::DEFAULT_NEGATIVE_TERMS),
        settings: compiled_settings(simple_input:, compiled_payload:, language_scope:, required_remote:, region_scope:, seniority_preset:)
      }

      apply_manual_overrides(attributes, manual_overrides)
    end

    def self.from_manual(form_attributes:, existing_settings: {}, active_default: true)
      form_attributes = form_attributes.deep_stringify_keys

      {
        name: form_attributes["name"],
        active: boolean_or_default(form_attributes["active"], active_default),
        required_remote: boolean_or_default(form_attributes["required_remote"], true),
        include_women_only: boolean_or_default(form_attributes["include_women_only"], false),
        language_scope: normalize_language_scope(form_attributes["language_scope"]),
        target_stacks: normalize_list(form_attributes["target_stacks_text"]),
        target_titles: normalize_list(form_attributes["target_titles_text"]),
        seniority_terms: normalize_list(form_attributes["seniority_terms_text"]),
        location_terms: normalize_list(form_attributes["location_terms_text"]),
        negative_terms: normalize_list(form_attributes["negative_terms_text"]),
        settings: existing_settings.presence || {}
      }
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

    def self.normalize_language_scope(value)
      value = value.to_s
      SearchProfile.language_scopes.key?(value) ? value : "both"
    end

    def self.normalize_seniority_preset(value)
      value = value.to_s
      SENIORITY_PRESETS.key?(value) ? value : "senior"
    end

    def self.normalize_region_scope(value)
      value = value.to_s
      REGION_TERMS.key?(value) ? value : "brazil_latam"
    end

    def self.location_terms_for(required_remote:, region_scope:)
      remote_terms = required_remote ? [ "remoto", "remote", "home office" ] : []
      normalize_list(remote_terms + REGION_TERMS.fetch(region_scope))
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

    def self.role_titles_for(language_scope)
      ROLE_TITLES_BY_LANGUAGE.fetch(language_scope, ROLE_TITLES_BY_LANGUAGE.fetch("both"))
    end

    def self.stack_alias_map(compiled_payload)
      Array(compiled_payload["stack_aliases"]).each_with_object({}) do |entry, result|
        canonical_stack = entry["canonical_stack"].to_s.downcase.squish
        next if canonical_stack.blank?

        result[canonical_stack] = normalize_list(entry["aliases"])
      end
    end

    def self.normalize_list(values)
      Array(values).flat_map { |value| value.to_s.split(/[\n,;]/) }
                   .map { |value| value.to_s.downcase.squish }
                   .reject(&:blank?)
                   .uniq
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
            "pt" => normalize_list(compiled_payload["title_variants_pt"]),
            "en" => normalize_list(compiled_payload["title_variants_en"])
          },
          "request_fingerprint" => compiled_payload["request_fingerprint"]
        }
      }
    end
    private_class_method :compiled_settings

    def self.apply_manual_overrides(attributes, manual_overrides)
      manual_overrides = manual_overrides.deep_stringify_keys

      MANUAL_OVERRIDE_FIELDS.each do |field, param_key|
        next if manual_overrides[param_key].blank?

        attributes[field] = normalize_list(manual_overrides[param_key])
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
