module JobDiscovery
  class Policy
    Result = Struct.new(
      :classification,
      :reason,
      :stack_tags,
      :score,
      :seniority,
      :remote_signal,
      :exclusion_reason,
      :search_profile,
      :eligibility_flags,
      keyword_init: true
    ) do
      def accepted?
        classification.in?(%i[ strong borderline ])
      end
    end

    STACK_SYNONYMS = {
      ".net" => [ ".net", "dotnet", "c#", "asp.net" ],
      "c#" => [ "c#", ".net", "dotnet", "asp.net" ],
      "java" => [ "java", "spring", "spring boot", "jvm" ],
      "ruby" => [ "ruby" ],
      "ruby on rails" => [ "ruby on rails", "rails" ],
      "rails" => [ "rails", "ruby on rails" ],
      "react" => [ "react", "reactjs", "react.js" ],
      "react native" => [ "react native", "react-native" ],
      "nextjs" => [ "nextjs", "next.js", "next js" ],
      "golang" => [ "golang", "go lang" ],
      "elixir" => [ "elixir", "phoenix" ],
      "recruiter" => [
        "recruiter",
        "tech recruiter",
        "technical recruiter",
        "talent acquisition",
        "recrutador",
        "recrutadora",
        "recrutamento",
        "recrutamento e selecao",
        "recrutamento e seleção"
      ],
      "rh" => [
        "rh",
        "recursos humanos",
        "human resources",
        "hr business partner",
        "hrbp",
        "people operations",
        "people ops",
        "people partner"
      ],
      "product" => [
        "product",
        "produto",
        "product manager",
        "gerente de produto",
        "gestor de produto",
        "product owner"
      ],
      "marketing" => [
        "marketing",
        "growth",
        "growth marketing",
        "performance marketing",
        "content marketing"
      ],
      "sales" => [
        "sales",
        "vendas",
        "account executive",
        "sales executive",
        "sales representative",
        "business development",
        "sdr",
        "bdr"
      ],
      "design" => [
        "design",
        "designer",
        "product designer",
        "ux designer",
        "ui designer",
        "user experience designer",
        "user interface designer"
      ],
      "customer_success" => [
        "customer success",
        "customer support",
        "client success",
        "sucesso do cliente",
        "support specialist"
      ],
      "finance" => [
        "finance",
        "financeiro",
        "financial analyst",
        "finance manager",
        "controller",
        "accounting",
        "contabilidade"
      ],
      "operations" => [
        "operations",
        "operacoes",
        "operações",
        "business operations",
        "strategy and operations",
        "ops"
      ],
      "project_management" => [
        "project manager",
        "program manager",
        "gerente de projetos",
        "gestor de projetos",
        "scrum master",
        "delivery manager"
      ],
      "data" => [
        "data",
        "dados",
        "data analyst",
        "data scientist",
        "data engineer",
        "analista de dados",
        "cientista de dados",
        "engenheiro de dados",
        "business intelligence",
        "bi"
      ]
    }.freeze
    TITLE_STACK_SYNONYMS = STACK_SYNONYMS.merge(
      "python" => [ "python", "django", "flask", "fastapi" ],
      "php" => [ "php", "laravel", "symfony" ],
      "node" => [ "node", "node.js", "nodejs", "nestjs", "nest.js", "express" ],
      "angular" => [ "angular", "angularjs" ],
      "vue" => [ "vue", "vue.js", "vuejs", "nuxt", "nuxt.js", "nuxtjs" ],
      "golang" => [ "golang", "go", "go lang" ],
      "elixir" => [ "elixir", "phoenix" ],
      "ios" => [ "ios", "swift" ],
      "android" => [ "android", "kotlin" ],
      "salesforce" => [ "salesforce", "apex", "lightning" ],
      "servicenow" => [ "servicenow", "service now" ]
    ).freeze
    COMPATIBLE_TITLE_STACKS = {
      "react" => [ "react native", "nextjs", "node" ],
      "react native" => [ "react" ],
      "nextjs" => [ "react", "node" ],
      "ruby on rails" => [ "rails", "ruby" ],
      "rails" => [ "ruby on rails", "ruby" ],
      ".net" => [ "c#" ],
      "c#" => [ ".net" ],
      "design" => [ "product" ]
    }.freeze
    DEFAULT_PROFILE_NAME = "Default senior Ruby/Rails/React".freeze
    PORTUGUESE_ROLE_TERMS = [
      "engenheiro de software",
      "engenheira de software",
      "engenheiro",
      "engenheira",
      "desenvolvedor",
      "desenvolvedora",
      "consultor",
      "consultora",
      "analista",
      "arquiteto",
      "arquiteta"
    ].freeze
    ENGLISH_ROLE_TERMS = [
      "software engineer",
      "engineer",
      "developer",
      "consultant",
      "architect"
    ].freeze
    NEUTRAL_ROLE_TERMS = [
      "frontend",
      "front-end",
      "backend",
      "back-end",
      "fullstack",
      "full-stack",
      "dev"
    ].freeze
    ONSITE_PATTERNS = /\b(presencial|on[-\s]?site|h[ií]brido|hybrid)\b/i
    REMOTE_PATTERNS = /\b(remot[oa]?|remote|home[\s-]?office|brasil|brazil|latam)\b/i
    WOMEN_ONLY_PATTERNS = /
      (
        (vaga|oportunidade|banco\s+de\s+talentos).{0,80}(mulher(?:es)?|women)
        |(afirmativ[ao]s?|exclusiv[ao]s?|preferencial(?:mente)?).{0,60}(mulher(?:es)?|women)
        |(mulher(?:es)?|women).{0,60}(afirmativ[ao]s?|exclusiv[ao]s?|preferencial(?:mente)?|only)
        |women[-\s]?only
        |only\s+women
        |female[-\s]?only
      )
    /ix
    CLOSED_PATTERNS = /\b(expirad[ao]|encerrad[ao]|indispon[ií]vel|closed|expired|unavailable|vencida)\b/i

    # Terms that mean "you may apply from anywhere". A posting carrying one of
    # these is never treated as geographically restricted, even when it also
    # names a foreign country (for example "Remote worldwide, HQ in Berlin").
    GLOBAL_ELIGIBILITY_PATTERNS = /
      \b(
        worldwide|world[-\s]?wide|global(?:ly)?|anywhere|any\s+country
        |work\s+from\s+anywhere|location\s+independent|no\s+location\s+restriction
      )\b
    /ix

    # The candidate's own region. Naming it anywhere in the posting clears the
    # foreign-restriction guard, since a role open to Brazil or LatAm is
    # reachable regardless of which other countries it also lists.
    HOME_REGION_PATTERNS = /\b(brasil|brazil|brazilian|latam|latin\s+america|south\s+america|americas)\b/i

    # Regions that exclude a candidate based in Brazil/LatAm when the posting
    # restricts hiring to them. Kept separate from the free-text country names
    # so a restriction phrase is only built from an explicit region.
    #
    # Unambiguous names, matched case-insensitively.
    FOREIGN_REGION_WORDS = [
      "usa", "united states", "canada", "united kingdom", "britain", "england", "ireland",
      "europe", "european union", "schengen",
      "germany", "france", "spain", "portugal", "netherlands", "poland", "italy",
      "australia", "new zealand", "india", "singapore", "japan", "israel"
    ].join("|").freeze

    # Short forms that collide with ordinary English when lowercased: "us" is
    # also the pronoun ("contact us", "join us", "work with us"), and "eu" is
    # Portuguese for "I". Matching those case-insensitively rejected perfectly
    # good postings, so these are matched only as written acronyms.
    FOREIGN_REGION_ACRONYMS = [
      "US", "U\\.S\\.", "U\\.S\\.A\\.", "UK", "U\\.K\\.", "EU", "EEA", "EMEA"
    ].join("|").freeze

    # Builds "<region>" as an alternation that keeps the acronyms case-sensitive
    # while the spelled-out names stay case-insensitive.
    FOREIGN_REGION_TERMS = "(?:(?i:#{FOREIGN_REGION_WORDS})|#{FOREIGN_REGION_ACRONYMS})".freeze

    # A restriction is only recognised when a region is paired with an explicit
    # limiting phrase ("US only", "must be based in Canada", "EU residents").
    # Merely mentioning a country is not a restriction: plenty of global roles
    # name the employer's headquarters.
    #
    # These patterns are deliberately NOT flagged `/i`: a global `/i` would undo
    # the case-sensitivity of the acronyms above and bring back the "contact us"
    # false positive. Case-insensitivity is applied per-fragment instead, via
    # `(?i:...)` on the surrounding English words and on the spelled-out regions.
    FOREIGN_RESTRICTION_PATTERNS = [
      /\b#{FOREIGN_REGION_TERMS}[-\s]*(?i:based|residents?|only)\b/,
      /(?i:\bonly\b)[^.;|]{0,40}\b#{FOREIGN_REGION_TERMS}\b/,
      /(?i:\b(?:must|need|required?)\s+(?:to\s+)?(?:be\s+)?(?:located|based|living|reside|residing|authorized|authorised|eligible)\b)[^.;|]{0,60}\b#{FOREIGN_REGION_TERMS}\b/,
      /(?i:\b(?:work(?:ing)?\s+)?(?:authorization|authorisation|eligibility|permit|visa)\b)[^.;|]{0,40}\b#{FOREIGN_REGION_TERMS}\b/,
      /\b#{FOREIGN_REGION_TERMS}\s+(?i:(?:work\s+)?(?:authorization|authorisation|citizens?|citizenship|nationals?|residency))\b/,
      /(?i:\b(?:restricted|limited|open)\s+to\b)[^.;|]{0,40}\b#{FOREIGN_REGION_TERMS}\b/,
      /(?i:\bwithin\s+the\s+)#{FOREIGN_REGION_TERMS}\b/
    ].freeze

    DefaultProfile = Struct.new(
      :id,
      :name,
      :target_stacks,
      :target_titles,
      :seniority_terms,
      :location_terms,
      :negative_terms,
      :language_scope,
      :required_remote,
      :include_women_only,
      keyword_init: true
    ) do
      def required_remote?
        required_remote
      end

      def include_women_only?
        include_women_only
      end

      def policy_contract
        JobDiscovery::PolicyContractSerializer.dump(self)
      end
    end

    Criteria = Struct.new(
      :profile,
      :language_scope,
      :title_stack_patterns,
      :context_stack_patterns,
      :allowed_catalog_stack_tags,
      :compiled_title_patterns,
      :catalog_title_stack_patterns,
      :title_patterns,
      :role_patterns,
      :seniority_patterns,
      :location_patterns,
      :negative_patterns,
      keyword_init: true
    )

    def self.contract(search_profile: nil)
      if search_profile
        search_profile.policy_contract
      else
        profiles = SearchProfile.active.ordered.to_a
        return default_profile.policy_contract if profiles.blank?

        {
          profiles: profiles.map(&:policy_contract),
          output: JobDiscovery::PolicyContractSerializer::OUTPUT_INSTRUCTION
        }
      end
    end

    def self.default_profile
      DefaultProfile.new(
        id: nil,
        name: DEFAULT_PROFILE_NAME,
        target_stacks: SearchProfiles::Vocabulary::DEFAULT_TARGET_STACKS,
        target_titles: SearchProfiles::Vocabulary::DEFAULT_TARGET_TITLES,
        seniority_terms: SearchProfiles::Vocabulary::DEFAULT_SENIORITY_TERMS,
        location_terms: SearchProfiles::Vocabulary::DEFAULT_LOCATION_TERMS,
        negative_terms: SearchProfiles::Vocabulary::DEFAULT_NEGATIVE_TERMS,
        language_scope: SearchProfiles::Vocabulary::DEFAULT_LANGUAGE_SCOPE,
        required_remote: true,
        include_women_only: false
      )
    end

    def self.rejected_result(reason, profile: nil)
      Result.new(
        classification: :rejected,
        reason:,
        stack_tags: [],
        score: 0,
        seniority: profile&.seniority_terms&.first.presence || "senior",
        remote_signal: nil,
        exclusion_reason: reason,
        search_profile: profile,
        eligibility_flags: []
      )
    end

    def initialize(search_profile: nil, search_profiles: nil)
      @profiles =
        if search_profile
          [ search_profile ]
        elsif search_profiles
          Array(search_profiles)
        else
          SearchProfile.active.ordered.to_a
        end.presence || [ self.class.default_profile ]

      @evaluators = @profiles.map do |profile|
        criteria = Policy::CriteriaBuilder.new(profile:).call
        Policy::CriteriaEvaluator.new(criteria:)
      end
    end

    def potential_match?(title)
      @evaluators.any? { |evaluator| evaluator.potential_match?(title) }
    end

    def classify(title:, remote_text:, location_text:, description:, source_slug:, posted_text:, published_at:)
      decisions = @evaluators.map do |evaluator|
        evaluator.classify(
          title:,
          remote_text:,
          location_text:,
          description:,
          source_slug:,
          posted_text:,
          published_at:
        )
      end

      decisions.select(&:accepted?).max_by(&:score) || decisions.max_by(&:score) || self.class.rejected_result("perfil de busca indisponivel")
    end
  end
end
