module JobSources
  class Catalog
    PORTUGAL_LOCATION_TERMS = [ "Portugal", "Lisboa", "Porto", "remoto Portugal", "remote Portugal" ].freeze
    PORTUGAL_SEED_QUERIES = [
      "remote jobs portugal",
      "trabalho remoto portugal",
      "product manager portugal remote",
      "tech recruiter portugal remote",
      "customer success portugal remote",
      "marketing portugal remote",
      "data analyst portugal remote",
      "software engineer portugal remote"
    ].freeze
    PORTUGAL_FALLBACK_REASON = "Fonte com cobertura de vagas em Portugal sem adapter Rails nativo; usar Codex fallback para busca por area/localidade, validar vaga ativa e postar pelo ingestion API.".freeze

    DEFAULTS = [
      {
        name: "Gupy",
        slug: "gupy",
        source_kind: :ats,
        base_url: "https://gupy.io",
        host: "gupy.io",
        priority: 10,
        adapter_key: "gupy_company_boards",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          board_urls: [
            "https://clicksign.gupy.io/",
            "https://memed.gupy.io/"
          ]
        }
      },
      { name: "Sólides", slug: "solides", source_kind: :ats, base_url: "https://vagas.solides.com.br", host: "vagas.solides.com.br", priority: 20, adapter_key: "solides_portal_vacancies", supports_backfill: true, scan_window_days: 20 },
      {
        name: "Recrutei",
        slug: "recrutei",
        source_kind: :ats,
        base_url: "https://jobs.recrutei.com.br",
        host: "jobs.recrutei.com.br",
        priority: 20,
        adapter_key: "recrutei_company_boards",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          company_labels: [ "maxxi" ],
          vacancy_urls: [
            "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior"
          ]
        }
      },
      {
        name: "Inhire",
        slug: "inhire",
        source_kind: :ats,
        base_url: "https://inhire.app",
        host: "inhire.app",
        priority: 20,
        adapter_key: "inhire_career_pages",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          career_page_slugs: %w[yandeh deal mb lighthouseit matera dotgroup inco casacred]
        }
      },
      {
        name: "Lever",
        slug: "lever",
        source_kind: :ats,
        base_url: "https://jobs.lever.co",
        host: "jobs.lever.co",
        priority: 20,
        adapter_key: "lever_company_boards",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          company_slugs: %w[ciandt jobgether decilegroup toptal]
        }
      },
      {
        name: "Greenhouse",
        slug: "greenhouse",
        source_kind: :ats,
        base_url: "https://job-boards.greenhouse.io",
        host: "job-boards.greenhouse.io",
        priority: 20,
        adapter_key: "greenhouse_boards_api",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          board_tokens: %w[rdsourcing fueledcareers]
        }
      },
      {
        name: "Ashby",
        slug: "ashby",
        source_kind: :ats,
        base_url: "https://jobs.ashbyhq.com",
        host: "jobs.ashbyhq.com",
        priority: 20,
        adapter_key: "ashby_job_board",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          board_slugs: %w[ruby-labs skydropx]
        }
      },
      {
        name: "JobTarget Hosted Apply",
        slug: "jobtarget-hosted-apply",
        source_kind: :ats,
        base_url: "https://hosted-apply.jobtarget.com",
        host: "hosted-apply.jobtarget.com",
        priority: 25,
        adapter_key: "jobtarget_hosted_apply",
        supports_backfill: true,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Provider orientado a job pages isoladas; usar Codex para descobrir novos links e o adapter Rails para canonizar, validar e revisitar URLs conhecidas.",
        scan_window_days: 20,
        settings: {
          seed_urls: [
            "https://hosted-apply.jobtarget.com/job/Senior-Full-Stack-Engineer-Ruby-on-Rails-React-LATAM-Remote-XnkxWLcVeRG8qTJZGuKGdy"
          ]
        }
      },
      {
        name: "Quickin",
        slug: "quickin",
        source_kind: :ats,
        base_url: "https://jobs.quickin.io",
        host: "jobs.quickin.io",
        priority: 25,
        adapter_key: "quickin_company_boards",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          company_slugs: %w[evtit botcity reply qintess],
          max_pages: 6
        }
      },
      { name: "Teamtailor", slug: "teamtailor", source_kind: :ats, base_url: "https://career.teamtailor.com", host: "teamtailor.com", priority: 20, adapter_key: "teamtailor_company_boards", supports_backfill: true, scan_window_days: 20 },
      { name: "Workable", slug: "workable", source_kind: :ats, base_url: "https://jobs.workable.com", host: "jobs.workable.com", priority: 20, adapter_key: "workable_global_api", supports_backfill: true, scan_window_days: 20 },
      {
        name: "SmartRecruiters",
        slug: "smartrecruiters",
        source_kind: :ats,
        base_url: "https://jobs.smartrecruiters.com",
        host: "smartrecruiters.com",
        priority: 20,
        adapter_key: "smartrecruiters_postings_api",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          company_identifiers: [ "smartrecruiters" ]
        }
      },
      { name: "Remotar", slug: "remotar", source_kind: :platform, base_url: "https://remotar.com.br", host: "remotar.com.br", priority: 30, adapter_key: "remotar_jobs_api", supports_backfill: true, scan_window_days: 20 },
      { name: "ProgramaThor", slug: "programathor", source_kind: :platform, base_url: "https://programathor.com.br", host: "programathor.com.br", priority: 30, adapter_key: "programathor_remote_senior", supports_backfill: true, scan_window_days: 20 },
      { name: "Coodesh", slug: "coodesh", source_kind: :platform, base_url: "https://coodesh.com", host: "coodesh.com", priority: 30, adapter_key: "coodesh_jobs_sitemap", supports_backfill: true, scan_window_days: 20 },
      { name: "Trampos", slug: "trampos", source_kind: :platform, base_url: "https://trampos.co", host: "trampos.co", priority: 30, adapter_key: "trampos_opportunities_api", supports_backfill: true, scan_window_days: 20 },
      {
        name: "Indeed",
        slug: "indeed",
        source_kind: :aggregator,
        base_url: "https://br.indeed.com",
        host: "br.indeed.com",
        priority: 35,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Busca publica protegida por Cloudflare para o worker Rails; usar Codex fallback com navegacao assistida, validar vaga ativa e postar pelo ingestion API.",
        scan_window_days: 20,
        settings: {
          search_hosts: [ "br.indeed.com", "pt.indeed.com" ],
          search_paths: [ "/jobs" ],
          default_location: "remoto",
          default_sort: "date",
          seed_queries: [
            "remote jobs",
            "vagas remotas",
            "product manager remoto",
            "tech recruiter remoto",
            "customer success remoto",
            "marketing remoto",
            "data analyst remoto",
            "software engineer portugal remote"
          ]
        }
      },
      {
        name: "ITJobs.pt",
        slug: "itjobs-pt",
        source_kind: :platform,
        base_url: "https://www.itjobs.pt",
        host: "itjobs.pt",
        priority: 36,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.itjobs.pt", "itjobs.pt" ],
          search_paths: [ "/emprego" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Teamlyzer Jobs",
        slug: "teamlyzer-jobs",
        source_kind: :platform,
        base_url: "https://pt.teamlyzer.com/companies/jobs",
        host: "pt.teamlyzer.com",
        priority: 36,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "pt.teamlyzer.com" ],
          search_paths: [ "/companies/jobs" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Landing.Jobs",
        slug: "landing-jobs",
        source_kind: :platform,
        base_url: "https://landing.jobs/jobs",
        host: "landing.jobs",
        priority: 36,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "landing.jobs" ],
          search_paths: [ "/jobs" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "EnglishJobs.pt",
        slug: "englishjobs-pt",
        source_kind: :platform,
        base_url: "https://englishjobs.pt/jobs/software",
        host: "englishjobs.pt",
        priority: 36,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "englishjobs.pt" ],
          search_paths: [ "/jobs/software", "/jobs/developer" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Net-Empregos",
        slug: "net-empregos-pt",
        source_kind: :aggregator,
        base_url: "https://www.net-empregos.com",
        host: "net-empregos.com",
        priority: 38,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.net-empregos.com", "net-empregos.com" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "SAPO Emprego",
        slug: "sapo-emprego",
        source_kind: :aggregator,
        base_url: "https://emprego.sapo.pt",
        host: "emprego.sapo.pt",
        priority: 38,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "emprego.sapo.pt" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Expresso Emprego",
        slug: "expresso-emprego",
        source_kind: :aggregator,
        base_url: "https://expressoemprego.pt",
        host: "expressoemprego.pt",
        priority: 39,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "expressoemprego.pt" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Alerta Emprego",
        slug: "alerta-emprego",
        source_kind: :aggregator,
        base_url: "https://www.alertaemprego.pt",
        host: "alertaemprego.pt",
        priority: 39,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.alertaemprego.pt", "alertaemprego.pt" ],
          search_paths: [ "/ver-ofertas-empregos" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "EURES",
        slug: "eures",
        source_kind: :aggregator,
        base_url: "https://europa.eu/eures/portal/jv-se/search",
        host: "europa.eu",
        priority: 39,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "europa.eu" ],
          search_paths: [ "/eures/portal/jv-se/search" ],
          regions: [ "portugal", "europe" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "EuroTechJobs",
        slug: "eurotechjobs",
        source_kind: :aggregator,
        base_url: "https://www.eurotechjobs.com/jobs/portugal",
        host: "eurotechjobs.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.eurotechjobs.com", "eurotechjobs.com" ],
          search_paths: [ "/jobs/portugal" ],
          regions: [ "portugal", "europe" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Built In Portugal",
        slug: "builtin-portugal",
        source_kind: :aggregator,
        base_url: "https://builtin.com/jobs/eu/portugal",
        host: "builtin.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "builtin.com" ],
          search_paths: [ "/jobs/eu/portugal" ],
          regions: [ "portugal", "europe" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Working Nomads Portugal",
        slug: "working-nomads-portugal",
        source_kind: :aggregator,
        base_url: "https://www.workingnomads.com/remote-portugal-jobs",
        host: "workingnomads.com",
        priority: 41,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.workingnomads.com", "workingnomads.com" ],
          search_paths: [ "/remote-portugal-jobs" ],
          regions: [ "portugal", "remote" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "We Are Distributed Portugal",
        slug: "we-are-distributed-portugal",
        source_kind: :aggregator,
        base_url: "https://wearedistributed.org/remote-jobs/portugal",
        host: "wearedistributed.org",
        priority: 41,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "wearedistributed.org" ],
          search_paths: [ "/remote-jobs/portugal" ],
          regions: [ "portugal", "remote" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Remote Rocketship Portugal",
        slug: "remote-rocketship-portugal",
        source_kind: :aggregator,
        base_url: "https://www.remoterocketship.com/country/portugal/jobs/software-engineer",
        host: "remoterocketship.com",
        priority: 41,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.remoterocketship.com", "remoterocketship.com" ],
          search_paths: [ "/country/portugal/jobs/software-engineer", "/country/portugal/jobs/software-developer" ],
          regions: [ "portugal", "remote" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Next Level Jobs Portugal",
        slug: "next-level-jobs-portugal",
        source_kind: :aggregator,
        base_url: "https://nextleveljobs.eu/country/pt",
        host: "nextleveljobs.eu",
        priority: 42,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "nextleveljobs.eu" ],
          search_paths: [ "/country/pt", "/remote" ],
          regions: [ "portugal", "europe", "remote" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "WeAreDevelopers Portugal",
        slug: "wearedevelopers-portugal",
        source_kind: :platform,
        base_url: "https://www.wearedevelopers.com/en/jobs/l/remote/portugal",
        host: "wearedevelopers.com",
        priority: 42,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.wearedevelopers.com", "wearedevelopers.com" ],
          search_paths: [ "/en/jobs/l/remote/portugal" ],
          regions: [ "portugal", "remote" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Talent.com Portugal",
        slug: "talent-com-portugal",
        source_kind: :aggregator,
        base_url: "https://pt.talent.com",
        host: "pt.talent.com",
        priority: 42,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "pt.talent.com" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Jobted Portugal",
        slug: "jobted-portugal",
        source_kind: :aggregator,
        base_url: "https://www.jobted.pt",
        host: "jobted.pt",
        priority: 42,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.jobted.pt", "jobted.pt" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Jooble Portugal",
        slug: "jooble-portugal",
        source_kind: :aggregator,
        base_url: "https://pt.jooble.org",
        host: "pt.jooble.org",
        priority: 42,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "pt.jooble.org", "jooble.org" ],
          search_paths: [ "/emprego", "/jobs/Portugal" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Glassdoor Portugal",
        slug: "glassdoor-portugal",
        source_kind: :aggregator,
        base_url: "https://www.glassdoor.com/Job/portugal-software-developer-jobs-SRCH_IL.0,8_IN195_KO9,27.htm",
        host: "glassdoor.com",
        priority: 43,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.glassdoor.com", "glassdoor.com" ],
          search_paths: [ "/Job/portugal-software-developer-jobs-SRCH_IL.0,8_IN195_KO9,27.htm" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Crossover Portugal",
        slug: "crossover-portugal",
        source_kind: :platform,
        base_url: "https://www.crossover.com/jobs/software-engineer/pt",
        host: "crossover.com",
        priority: 43,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.crossover.com", "crossover.com" ],
          search_paths: [ "/jobs/software-engineer/pt", "/jobs/full-stack-developer/pt" ],
          regions: [ "portugal", "remote" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Arc Portugal",
        slug: "arc-portugal",
        source_kind: :platform,
        base_url: "https://arc.dev/en-pt/remote-jobs",
        host: "arc.dev",
        priority: 43,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "arc.dev" ],
          search_paths: [ "/en-pt/remote-jobs" ],
          regions: [ "portugal", "remote" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Startup Jobs Lisbon",
        slug: "startup-jobs-lisbon",
        source_kind: :platform,
        base_url: "https://startup.jobs/locations/lisbon/software-engineer",
        host: "startup.jobs",
        priority: 43,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "startup.jobs" ],
          search_paths: [ "/locations/lisbon/software-engineer" ],
          regions: [ "portugal" ],
          default_location: "Lisboa",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Randstad Portugal",
        slug: "randstad-portugal",
        source_kind: :platform,
        base_url: "https://www.randstad.pt/empregos",
        host: "randstad.pt",
        priority: 44,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.randstad.pt", "randstad.pt" ],
          search_paths: [ "/empregos", "/software-developers" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Randstad Digital Portugal",
        slug: "randstad-digital-portugal",
        source_kind: :company,
        base_url: "https://www.randstaddigital.pt/pt/carreiras",
        host: "randstaddigital.pt",
        priority: 44,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.randstaddigital.pt", "randstaddigital.pt" ],
          search_paths: [ "/pt/carreiras" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Hays Portugal",
        slug: "hays-portugal",
        source_kind: :platform,
        base_url: "https://www.hays.pt",
        host: "hays.pt",
        priority: 44,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.hays.pt", "hays.pt" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Adecco Portugal",
        slug: "adecco-portugal",
        source_kind: :platform,
        base_url: "https://www.adecco.com/pt-pt/ofertas-emprego",
        host: "adecco.com",
        priority: 44,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.adecco.com" ],
          search_paths: [ "/pt-pt/ofertas-emprego" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Michael Page Portugal",
        slug: "michael-page-portugal",
        source_kind: :platform,
        base_url: "https://www.michaelpage.pt/jobs/information-technology",
        host: "michaelpage.pt",
        priority: 44,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.michaelpage.pt", "michaelpage.pt" ],
          search_paths: [ "/jobs/information-technology", "/jobs/desenvolvimento-programacao/portugal" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Robert Walters Portugal",
        slug: "robert-walters-portugal",
        source_kind: :platform,
        base_url: "https://www.robertwalters.pt/ofertas-emprego.html",
        host: "robertwalters.pt",
        priority: 44,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.robertwalters.pt", "robertwalters.pt" ],
          search_paths: [ "/ofertas-emprego.html" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Talent Portugal",
        slug: "talent-portugal",
        source_kind: :platform,
        base_url: "https://talentportugal.com",
        host: "talentportugal.com",
        priority: 44,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "talentportugal.com" ],
          regions: [ "portugal" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "APInfo",
        slug: "apinfo",
        source_kind: :platform,
        base_url: "https://apinfo.com",
        host: "apinfo.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Fonte publica rate-limited; usar Codex para descoberta assistida e ingestion API.",
        scan_window_days: 20
      },
      {
        name: "RubyOnRemote",
        slug: "rubyonremote",
        source_kind: :platform,
        base_url: "https://rubyonremote.com",
        host: "rubyonremote.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Fonte protegida por Cloudflare para o worker Rails; usar Codex fallback quando houver busca assistida.",
        scan_window_days: 20
      },
      {
        name: "Landor ATS",
        slug: "landor-ats",
        source_kind: :ats,
        base_url: "https://ats.landor.com.br",
        host: "ats.landor.com.br",
        priority: 25,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "ATS SPA em Flutter com dados carregados no cliente; usar Codex fallback com links canonicos de candidatura.",
        scan_window_days: 20,
        settings: {
          seed_urls: [
            "https://ats.landor.com.br/vaga-candidatura/51b51917-ffd9-4485-8239-8a986498d109"
          ]
        }
      },
      {
        name: "Get Great Careers",
        slug: "get-great-careers",
        source_kind: :aggregator,
        base_url: "https://www.getgreatcareers.com/jobs",
        host: "getgreatcareers.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Busca SPA orientada por query; usar Codex fallback e preferir link oficial ou ATS antes de reportar.",
        scan_window_days: 20,
        settings: {
          seed_urls: [
            "https://www.getgreatcareers.com/jobs?keyword=ruby%20on%20rails&location=Remote,%20OR,%20USA&radius=20miles"
          ]
        }
      },
      {
        name: "LinkedIn Jobs",
        slug: "linkedin",
        source_kind: :aggregator,
        base_url: "https://www.linkedin.com/jobs",
        host: "linkedin.com",
        priority: 45,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Busca publica depende de query por perfil e limites anti-bot; usar Codex fallback e canonizar para ATS ou careers page quando possivel.",
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.linkedin.com", "br.linkedin.com", "pt.linkedin.com" ],
          guest_search_path: "/jobs-guest/jobs/api/seeMoreJobPostings/search"
        }
      },
      {
        name: "iCIMS",
        slug: "icims",
        source_kind: :ats,
        base_url: "https://careers.icims.com",
        host: "careers.icims.com",
        priority: 45,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "ATS amplo sem adapter Rails ainda; usar busca site:careers.icims.com e canonizar para pagina oficial antes da ingestao.",
        scan_window_days: 20,
        settings: {
          search_hosts: [ "careers.icims.com" ]
        }
      },
      {
        name: "Jobvite",
        slug: "jobvite",
        source_kind: :ats,
        base_url: "https://jobs.jobvite.com",
        host: "jobs.jobvite.com",
        priority: 45,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "ATS amplo sem adapter Rails ainda; usar busca site:jobs.jobvite.com e canonizar para pagina oficial antes da ingestao.",
        scan_window_days: 20,
        settings: {
          search_hosts: [ "jobs.jobvite.com" ]
        }
      },
      {
        name: "Workday",
        slug: "workday",
        source_kind: :ats,
        base_url: "https://wd1.myworkdayjobs.com",
        host: "myworkdayjobs.com",
        priority: 45,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "ATS amplo e variavel por tenant; usar busca site:myworkdayjobs.com e canonizar para a pagina de vaga antes da ingestao.",
        scan_window_days: 20,
        settings: {
          search_hosts: [ "wd1.myworkdayjobs.com", "myworkdayjobs.com" ]
        }
      },
      {
        name: "BambooHR",
        slug: "bamboohr",
        source_kind: :ats,
        base_url: "https://jobs.bamboohr.com",
        host: "jobs.bamboohr.com",
        priority: 45,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "ATS amplo sem adapter Rails ainda; usar busca site:jobs.bamboohr.com e canonizar para pagina oficial antes da ingestao.",
        scan_window_days: 20,
        settings: {
          search_hosts: [ "jobs.bamboohr.com" ]
        }
      },
      {
        name: "JazzHR",
        slug: "jazzhr",
        source_kind: :ats,
        base_url: "https://apply.jazz.co",
        host: "apply.jazz.co",
        priority: 45,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "ATS amplo sem adapter Rails ainda; usar busca site:apply.jazz.co e canonizar para pagina oficial antes da ingestao.",
        scan_window_days: 20,
        settings: {
          search_hosts: [ "apply.jazz.co" ]
        }
      },
      {
        name: "NetVagas",
        slug: "netvagas",
        source_kind: :aggregator,
        base_url: "https://www.netvagas.com.br",
        host: "netvagas.com.br",
        priority: 45,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Portal aberto sem adapter curado ainda; usar Codex fallback para descoberta dirigida por titulo e recencia.",
        scan_window_days: 20
      },
      {
        name: "Remotely Works",
        slug: "remotely-works",
        source_kind: :platform,
        base_url: "https://platform.remotely.works",
        host: "platform.remotely.works",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Plataforma SPA com fluxo JS e possivel Turnstile; usar Codex fallback para descoberta e validacao.",
        scan_window_days: 20,
        settings: {
          seed_urls: [
            "https://platform.remotely.works/apply?utm_source=linkedin&utm_medium=admsg&utm_campaign=SeniorFullstackEngineer&li_fat_id=c2705c47-51c6-4e6e-ad60-e8f3d9ffb933"
          ]
        }
      }
    ].freeze

    def self.defaults
      DEFAULTS
    end

    def self.seed!(relation: JobSource)
      defaults.each do |attributes|
        source = relation.find_or_initialize_by(slug: attributes.fetch(:slug))
        if source.new_record?
          source.assign_attributes(attributes)
        else
          apply_defaults!(source, attributes)
        end
        source.save!
      end
    end

    def self.supported_backfill_adapter?(adapter_key)
      JobDiscovery::Registry.supports?(adapter_key)
    end

    def self.apply_defaults!(source, attributes)
      attributes.each do |key, value|
        if key.to_sym == :settings
          source.settings = default_settings(value).deep_merge(source.settings || {})
          next
        end

        source.public_send("#{key}=", value) if source.public_send(key).nil?
      end
    end
    private_class_method :apply_defaults!

    def self.default_settings(value)
      value.to_h.deep_stringify_keys
    end
    private_class_method :default_settings
  end
end
