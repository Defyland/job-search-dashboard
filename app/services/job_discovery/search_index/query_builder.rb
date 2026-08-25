module JobDiscovery
  module SearchIndex
    class QueryBuilder
      DEFAULT_LIMIT = 600
      MAX_PHRASES_PER_QUERY = 10
      MAX_ROLE_TERMS_PER_QUERY = 8
      MAX_NEGATIVE_TERMS = 6

      TARGETS = [
        { source_slug: "ashby", host: "jobs.ashbyhq.com", setting_key: "board_slugs" },
        { source_slug: "greenhouse", host: "job-boards.greenhouse.io", setting_key: "board_tokens" },
        { source_slug: "greenhouse", host: "boards.greenhouse.io", setting_key: "board_tokens" },
        { source_slug: "lever", host: "jobs.lever.co", setting_key: "company_slugs" },
        { source_slug: "smartrecruiters", host: "jobs.smartrecruiters.com", setting_key: "company_identifiers" },
        { source_slug: "quickin", host: "jobs.quickin.io", setting_key: "company_slugs" },
        { source_slug: "recrutei", host: "jobs.recrutei.com.br", setting_key: "company_labels" },
        { source_slug: "workable", host: "jobs.workable.com", setting_key: nil },
        { source_slug: "workable", host: "careers.workable.com", setting_key: nil },
        { source_slug: "icims", host: "careers.icims.com", setting_key: nil },
        { source_slug: "jobvite", host: "jobs.jobvite.com", setting_key: nil },
        { source_slug: "workday", host: "wd1.myworkdayjobs.com", setting_key: nil },
        { source_slug: "workday", host: "myworkdayjobs.com", setting_key: nil },
        { source_slug: "bamboohr", host: "jobs.bamboohr.com", setting_key: nil },
        { source_slug: "jazzhr", host: "apply.jazz.co", setting_key: nil },
        { source_slug: "indeed", host: "br.indeed.com", setting_key: nil },
        { source_slug: "indeed", host: "pt.indeed.com", setting_key: nil },
        { source_slug: "linkedin", host: "pt.linkedin.com", setting_key: nil },
        { source_slug: "itjobs-pt", host: "www.itjobs.pt", setting_key: nil },
        { source_slug: "teamlyzer-jobs", host: "pt.teamlyzer.com/companies/jobs", setting_key: nil },
        { source_slug: "landing-jobs", host: "landing.jobs/jobs", setting_key: nil },
        { source_slug: "englishjobs-pt", host: "englishjobs.pt/jobs", setting_key: nil },
        { source_slug: "net-empregos-pt", host: "www.net-empregos.com", setting_key: nil },
        { source_slug: "sapo-emprego", host: "emprego.sapo.pt", setting_key: nil },
        { source_slug: "expresso-emprego", host: "expressoemprego.pt", setting_key: nil },
        { source_slug: "alerta-emprego", host: "www.alertaemprego.pt", setting_key: nil },
        { source_slug: "eures", host: "europa.eu/eures/portal/jv-se/search", setting_key: nil },
        { source_slug: "eurotechjobs", host: "www.eurotechjobs.com/jobs/portugal", setting_key: nil },
        { source_slug: "builtin-portugal", host: "builtin.com/jobs/eu/portugal", setting_key: nil },
        { source_slug: "working-nomads-portugal", host: "www.workingnomads.com/remote-portugal-jobs", setting_key: nil },
        { source_slug: "we-are-distributed-portugal", host: "wearedistributed.org/remote-jobs/portugal", setting_key: nil },
        { source_slug: "remote-rocketship-portugal", host: "www.remoterocketship.com/country/portugal/jobs", setting_key: nil },
        { source_slug: "next-level-jobs-portugal", host: "nextleveljobs.eu/country/pt", setting_key: nil },
        { source_slug: "wearedevelopers-portugal", host: "www.wearedevelopers.com/en/jobs/l/remote/portugal", setting_key: nil },
        { source_slug: "talent-com-portugal", host: "pt.talent.com", setting_key: nil },
        { source_slug: "jobted-portugal", host: "www.jobted.pt", setting_key: nil },
        { source_slug: "jooble-portugal", host: "pt.jooble.org", setting_key: nil },
        { source_slug: "glassdoor-portugal", host: "www.glassdoor.com/Job/portugal", setting_key: nil },
        { source_slug: "crossover-portugal", host: "www.crossover.com/jobs/pt", setting_key: nil },
        { source_slug: "arc-portugal", host: "arc.dev/en-pt/remote-jobs", setting_key: nil },
        { source_slug: "startup-jobs-lisbon", host: "startup.jobs/locations/lisbon", setting_key: nil },
        { source_slug: "randstad-portugal", host: "www.randstad.pt/empregos", setting_key: nil },
        { source_slug: "randstad-digital-portugal", host: "www.randstaddigital.pt/pt/carreiras", setting_key: nil },
        { source_slug: "hays-portugal", host: "www.hays.pt", setting_key: nil },
        { source_slug: "adecco-portugal", host: "www.adecco.com/pt-pt/ofertas-emprego", setting_key: nil },
        { source_slug: "michael-page-portugal", host: "www.michaelpage.pt/jobs", setting_key: nil },
        { source_slug: "robert-walters-portugal", host: "www.robertwalters.pt/ofertas-emprego.html", setting_key: nil },
        { source_slug: "talent-portugal", host: "talentportugal.com", setting_key: nil },
        { source_slug: "turnkey-staffing", host: "turnkeystaffing.com/career", setting_key: nil },
        { source_slug: "clouddevs", host: "clouddevs.com/jobs", setting_key: nil },
        { source_slug: "hire-with-near", host: "jobs.hirewithnear.com", setting_key: nil },
        { source_slug: "weknow", host: "weknowinc.com/careers/work-at-weknow", setting_key: nil },
        { source_slug: "revelo", host: "careers.revelo.com", setting_key: nil },
        { source_slug: "awana", host: "www.awana.io/job-openings.html", setting_key: nil },
        { source_slug: "tecla", host: "www.tecla.io/join", setting_key: nil },
        { source_slug: "vanhack", host: "vanhack.com/get-hired", setting_key: nil },
        { source_slug: "kake", host: "kake.co/jobs", setting_key: nil },
        { source_slug: "zipdev", host: "www.zipdev.com/careers", setting_key: nil },
        { source_slug: "dataannotation-coding", host: "www.dataannotation.tech/coding", setting_key: nil },
        { source_slug: "proxify-careers", host: "career.proxify.io/ruby-on-rails/vacancies", setting_key: nil, stacks: [ "ruby", "ruby on rails", "rails" ] },
        { source_slug: "remote-jobs-finder", host: "remotejobsfinder.co/en", setting_key: nil },
        { source_slug: "wellfound", host: "wellfound.com", setting_key: nil },
        { source_slug: "jobleads-portugal", host: "www.jobleads.com/pt/jobs", setting_key: nil },
        { source_slug: "job-board-search", host: "jobboardsearch.com", setting_key: nil },
        { source_slug: "python-job-board", host: "www.python.org/jobs", setting_key: nil, stacks: %w[python django flask fastapi] },
        { source_slug: "django-community-jobs", host: "www.djangoproject.com/community/jobs", setting_key: nil, stacks: %w[python django] },
        { source_slug: "javascript-jobs", host: "javascript.jobs", setting_key: nil, stacks: [ "javascript", "typescript", "node", "react", "react native", "nextjs", "angular", "vue" ] },
        { source_slug: "react-jobs", host: "reactjobs.io", setting_key: nil, stacks: [ "react", "react native", "nextjs" ] },
        { source_slug: "vue-jobs", host: "vuejobs.com", setting_key: nil, stacks: %w[vue nuxt javascript typescript] },
        { source_slug: "angular-work", host: "angular.work", setting_key: nil, stacks: %w[angular javascript typescript] },
        { source_slug: "larajobs", host: "larajobs.com", setting_key: nil, stacks: %w[php laravel] },
        { source_slug: "symfony-jobs", host: "symfony.com/jobs", setting_key: nil, stacks: %w[php symfony] },
        { source_slug: "elixir-jobs", host: "elixirjobs.net", setting_key: nil, stacks: %w[elixir phoenix erlang] },
        { source_slug: "golang-projects", host: "www.golangprojects.com", setting_key: nil, stacks: %w[go golang] },
        { source_slug: "rust-jobs-dev", host: "rustjobs.dev", setting_key: nil, stacks: %w[rust] },
        { source_slug: "kotlin-brasil-jobs", host: "kotlin.dev.br/vagas", setting_key: nil, stacks: %w[kotlin android java] },
        { source_slug: "mobile-career-swift", host: "mobile.career/swift-developer-jobs", setting_key: nil, stacks: %w[swift ios macos] },
        { source_slug: "cpp-jobs", host: "cppjobs.it", setting_key: nil, stacks: [ "c", "c++", "cpp" ] },
        { source_slug: "embedded-jobs", host: "embedded.jobs/embedded-c%2B%2B-jobs", setting_key: nil, stacks: [ "c", "c++", "cpp", "rust", "embedded" ] }
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
        query_groups = @search_profiles.flat_map { |profile| query_groups_for_profile(profile) }
        ordered_queries = if limit && limit < query_groups.length
          query_groups.flatten
        else
          interleave_query_groups(query_groups)
        end

        ordered_queries.first(limit)
      end

      private
        def query_groups_for_profile(profile)
          stacks = normalize_list(profile.target_stacks)
          stacks.map do |stack|
            targets_for_stack(stack).map do |target|
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

        def interleave_query_groups(query_groups)
          max_group_size = query_groups.map(&:length).max.to_i

          (0...max_group_size).flat_map do |index|
            query_groups.filter_map { |group| group[index] }
          end
        end

        def targets_for_stack(stack)
          stack_terms = stack_terms_for(stack)

          @targets.select do |target|
            target_stacks = normalize_list(target[:stacks])
            target_stacks.blank? || target_stacks.intersect?(stack_terms)
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

          phrases =
            if SearchProfiles::Vocabulary.non_tech_role_stack?([ stack ])
              stack_terms.flat_map do |stack_term|
                seniority_terms.flat_map do |seniority|
                  [
                    "#{seniority} #{stack_term}",
                    "#{stack_term} #{seniority}"
                  ]
                end
              end
            else
              roles = role_terms_for(profile).first(MAX_ROLE_TERMS_PER_QUERY)
              stack_terms.flat_map do |stack_term|
                seniority_terms.flat_map do |seniority|
                  [
                    "#{seniority} #{stack_term}",
                    "#{stack_term} #{seniority}",
                    *roles.map { |role| "#{role} #{stack_term} #{seniority}" }
                  ]
                end
              end
            end

          generated_titles = generated_titles_for(profile, stack)
          seniority_phrases = normalize_list(phrases).select do |phrase|
            seniority_terms.any? { |seniority| term_match?(phrase, seniority) }
          end
          stack_seniority_phrases = [ "#{seniority_terms.first} #{stack_terms.first}" ]
          if %w[elixir golang].include?(stack)
            stack_seniority_phrases.concat(stack_terms.drop(1).map { |stack_term| "#{seniority_terms.first} #{stack_term}" })
          end

          normalize_list(stack_seniority_phrases + seniority_phrases.first(2) + generated_titles + phrases).first(MAX_PHRASES_PER_QUERY)
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

          normalized_patterns = stack_terms_for(stack)
          normalize_list(titles).select do |title|
            matching_terms = normalized_patterns.select { |term| term_match?(title, term) }
            next false if matching_terms.blank?

            strongest_match = matching_terms.map(&:length).max
            conflicting_terms = normalize_list(profile.target_stacks).reject { |target| target == stack }
              .flat_map { |target| stack_terms_for(target) }
              .uniq

            conflicting_terms.none? do |term|
              term.length > strongest_match && term_match?(title, term)
            end
          end
        end

        def role_terms_for(profile)
          if SearchProfiles::Vocabulary.non_tech_role_stack?(profile.target_stacks)
            return SearchProfiles::Vocabulary.role_titles_for(profile.language_scope.to_s, target_stacks: profile.target_stacks)
          end

          case profile.language_scope.to_s
          when "portuguese"
            [
              "desenvolvedor",
              "desenvolvedora",
              "engenheiro de software",
              "engenheira de software",
              "frontend",
              "front-end",
              "engenheiro",
              "engenheira",
              "backend",
              "back-end",
              "fullstack",
              "full-stack"
            ]
          when "english"
            [
              "developer",
              "engineer",
              "software engineer",
              "frontend",
              "front-end",
              "backend",
              "back-end",
              "fullstack",
              "full-stack"
            ]
          else
            [
              "desenvolvedor",
              "desenvolvedora",
              "engenheiro de software",
              "engenheira de software",
              "developer",
              "software engineer",
              "frontend",
              "front-end",
              "backend",
              "back-end",
              "fullstack",
              "full-stack"
            ]
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

        def term_match?(input, term)
          normalized_input = input.to_s.downcase.squish
          normalized_term = SearchProfiles::Vocabulary.normalize(term)
          return false if normalized_input.blank? || normalized_term.blank?

          pattern = Regexp.escape(normalized_term).gsub("\\ ", "[\\s-]+")
          normalized_input.match?(/(?<![[:alnum:]])#{pattern}(?![[:alnum:]])/i)
        end

        def normalize_list(values)
          SearchProfiles::Vocabulary.normalize_list(values)
        end
    end
  end
end
