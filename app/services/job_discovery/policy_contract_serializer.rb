module JobDiscovery
  class PolicyContractSerializer
    OUTPUT_INSTRUCTION = "POST accepted strong/borderline jobs and useful rejections to /api/v1/job_ingestions".freeze

    def self.dump(profile)
      {
        profile_id: profile.id,
        profile_name: profile.name,
        seniority_terms: Array(profile.seniority_terms),
        stack_terms: Array(profile.target_stacks),
        title_terms: Array(profile.target_titles),
        language_scope: profile.language_scope.to_s.presence || "both",
        location_terms: Array(profile.location_terms),
        required_remote: profile.required_remote?,
        include_women_only: profile.include_women_only?,
        exclude_terms: exclude_terms_for(profile),
        output: OUTPUT_INSTRUCTION
      }
    end

    def self.exclude_terms_for(profile)
      return profile.effective_exclude_terms if profile.respond_to?(:effective_exclude_terms)

      terms = Array(profile.negative_terms).dup
      terms + (profile.include_women_only? ? [] : SearchProfiles::Vocabulary::WOMEN_ONLY_EXCLUDE_TERMS)
    end
    private_class_method :exclude_terms_for
  end
end
