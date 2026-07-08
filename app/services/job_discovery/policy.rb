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
      "golang" => [ "golang" ],
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
