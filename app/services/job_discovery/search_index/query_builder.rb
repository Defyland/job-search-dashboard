module JobDiscovery
  module SearchIndex
    class QueryBuilder
      DEFAULT_LIMIT = 120
      MAX_PHRASES_PER_QUERY = 6
      MAX_NEGATIVE_TERMS = 6

      TARGETS = [
        { source_slug: "ashby", host: "jobs.ashbyhq.com", setting_key: "board_slugs" },
        { source_slug: "greenhouse", host: "job-boards.greenhouse.io", setting_key: "board_tokens" },
        { source_slug: "greenhouse", host: "boards.greenhouse.io", setting_key: "board_tokens" },
        { source_slug: "lever", host: "jobs.lever.co", setting_key: "company_slugs" },
        { source_slug: "smartrecruiters", host: "jobs.smartrecruiters.com", setting_key: "company_identifiers" },
        { source_slug: "quickin", host: "jobs.quickin.io", setting_key: "company_slugs" },
        { source_slug: "workable", host: "jobs.workable.com", setting_key: nil },
        { source_slug: "workable", host: "careers.workable.com", setting_key: nil },
        { source_slug: "icims", host: "careers.icims.com", setting_key: nil },
        { source_slug: "jobvite", host: "jobs.jobvite.com", setting_key: nil },
        { source_slug: "workday", host: "wd1.myworkdayjobs.com", setting_key: nil },
        { source_slug: "workday", host: "myworkdayjobs.com", setting_key: nil },
        { source_slug: "bamboohr", host: "jobs.bamboohr.com", setting_key: nil },
        { source_slug: "jazzhr", host: "apply.jazz.co", setting_key: nil },
        { source_slug: "indeed", host: "br.indeed.com", setting_key: nil }
      ].freeze

      Query = Struct.new(
        :source_slug,
        :host,
        :search_profile_id,
        :search_profile_name,
        :target_stack,
        :query,
        keyword_init: true
      ) do
        def to_h
          {
            source_slug:,
            host:,
            search_profile_id:,
            search_profile_name:,
            target_stack:,
            query:
          }
        end
      end

      def initialize(search_profiles:, targets: TARGETS)
        @search_profiles = Array(search_profiles).presence || [ JobDiscovery::Policy.default_profile ]
        @targets = Array(targets)
      end

      def queries(limit: DEFAULT_LIMIT)
        @search_profiles.flat_map { |profile| queries_for_profile(profile) }.first(limit)
      end

      private
        def queries_for_profile(profile)
          stacks = normalize_list(profile.target_stacks).first(6)
          stacks.flat_map do |stack|
            @targets.map do |target|
              Query.new(
                source_slug: target.fetch(:source_slug),
                host: target.fetch(:host),
                search_profile_id: profile.id,
                search_profile_name: profile.name,
                target_stack: stack,
                query: query_for(profile:, stack:, host: target.fetch(:host))
              )
            end
          end
        end

        def query_for(profile:, stack:, host:)
          [
            "site:#{host}",
            boolean_group(title_phrases(profile, stack)),
            remote_group(profile),
            negative_terms(profile)
          ].compact_blank.join(" ")
        end

        def title_phrases(profile, stack)
          seniority_terms = normalize_list(profile.seniority_terms).first(2)
          seniority_terms = [ "senior" ] if seniority_terms.blank?
          stack_terms = stack_terms_for(stack).first(3)
          roles = role_terms_for(profile).first(4)

          phrases = stack_terms.flat_map do |stack_term|
            seniority_terms.flat_map do |seniority|
              [
                "#{seniority} #{stack_term}",
                "#{stack_term} #{seniority}",
                *roles.map { |role| "#{role} #{stack_term} #{seniority}" }
              ]
            end
          end

          normalize_list(generated_titles_for(profile, stack) + phrases).first(MAX_PHRASES_PER_QUERY)
        end

        def generated_titles_for(profile, stack)
          return [] unless profile.respond_to?(:compiler_settings)

          generated_titles = profile.compiler_settings.fetch("generated_titles", {})
          titles = case profile.language_scope.to_s
          when "portuguese"
            generated_titles.fetch("pt", [])
          when "english"
            generated_titles.fetch("en", [])
          else
            Array(generated_titles.fetch("pt", [])) + Array(generated_titles.fetch("en", []))
          end

          stack_patterns = JobDiscovery::Policy::TITLE_STACK_SYNONYMS.fetch(stack, [ stack ])
          normalized_patterns = normalize_list([ stack ] + stack_patterns)
          normalize_list(titles).select do |title|
            normalized_patterns.any? { |term| title.include?(term) }
          end
        end

        def role_terms_for(profile)
          case profile.language_scope.to_s
          when "portuguese"
            %w[desenvolvedor engenheiro] + [ "engenheiro de software" ]
          when "english"
            [ "developer", "engineer", "software engineer" ]
          else
            [ "desenvolvedor", "engenheiro de software", "developer", "software engineer" ]
          end
        end

        def remote_group(profile)
          return unless !profile.respond_to?(:required_remote?) || profile.required_remote?

          terms = normalize_list(profile.location_terms).presence || %w[remoto remote latam brasil brazil]
          boolean_group(terms.first(6))
        end

        def negative_terms(profile)
          normalize_list(profile.negative_terms).first(MAX_NEGATIVE_TERMS).map do |term|
            "-#{quoted(term)}"
          end.join(" ")
        end

        def boolean_group(terms)
          terms = normalize_list(terms)
          return if terms.blank?
          return quoted(terms.first) if terms.one?

          "(#{terms.map { |term| quoted(term) }.join(" OR ")})"
        end

        def quoted(term)
          %("#{term.to_s.delete('"')}")
        end

        def stack_terms_for(stack)
          normalize_list([ stack ] + JobDiscovery::Policy::TITLE_STACK_SYNONYMS.fetch(stack, []))
        end

        def normalize_list(values)
          SearchProfiles::Vocabulary.normalize_list(values)
        end
    end
  end
end
