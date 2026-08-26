module JobSources
  class Catalog
    PORTUGAL_LOCATION_TERMS = [ "Portugal", "Lisboa", "Porto", "remoto Portugal", "remote Portugal" ].freeze
    LATAM_LOCATION_TERMS = [
      "Latin America",
      "LATAM",
      "Argentina",
      "Brazil",
      "Colombia",
      "Costa Rica",
      "Ecuador",
      "Mexico",
      "Peru",
      "Uruguay",
      "remote",
      "remoto"
    ].freeze
    PORTUGAL_SEED_QUERIES = [
      "remote jobs portugal",
      "trabalho remoto portugal",
      "product manager portugal remote",
      "tech recruiter portugal remote",
      "customer success portugal remote",
      "marketing portugal remote",
      "data analyst portugal remote",
      "sales portugal remote",
      "finance portugal remote",
      "operations portugal remote",
      "software engineer portugal remote"
    ].freeze
    PORTUGAL_FALLBACK_REASON = "Fonte com cobertura de vagas em Portugal sem adapter Rails nativo; usar Codex fallback para busca por area/localidade, validar vaga ativa e postar pelo ingestion API.".freeze
    LATAM_FALLBACK_REASON = "Fonte de staffing ou carreira remota na America Latina; usar Codex fallback para descobrir vagas publicas, validar pagina ativa e postar pelo ingestion API.".freeze
    LANGUAGE_BOARD_FALLBACK_REASON = "Portal especializado por linguagem ou framework sem adapter Rails nativo; usar Codex fallback com as stacks configuradas, validar recencia e canonizar para a pagina de candidatura.".freeze
    LANGUAGE_BOARD_SPECS = [
      { name: "Python Job Board", slug: "python-job-board", base_url: "https://www.python.org/jobs", host: "python.org", stacks: %w[python django flask fastapi] },
      { name: "Django Community Jobs", slug: "django-community-jobs", base_url: "https://www.djangoproject.com/community/jobs", host: "djangoproject.com", stacks: %w[python django] },
      { name: "JavaScript Jobs", slug: "javascript-jobs", base_url: "https://javascript.jobs", host: "javascript.jobs", stacks: [ "javascript", "typescript", "node", "react", "react native", "nextjs", "angular", "vue" ] },
      { name: "React Jobs", slug: "react-jobs", base_url: "https://reactjobs.io", host: "reactjobs.io", stacks: [ "react", "react native", "nextjs" ] },
      { name: "VueJobs", slug: "vue-jobs", base_url: "https://vuejobs.com", host: "vuejobs.com", stacks: %w[vue nuxt javascript typescript] },
      { name: "Angular.work", slug: "angular-work", base_url: "https://angular.work", host: "angular.work", stacks: %w[angular javascript typescript] },
      { name: "LaraJobs", slug: "larajobs", base_url: "https://larajobs.com", host: "larajobs.com", stacks: %w[php laravel] },
      { name: "Symfony Jobs", slug: "symfony-jobs", base_url: "https://symfony.com/jobs", host: "symfony.com", stacks: %w[php symfony] },
      { name: "Elixir Jobs", slug: "elixir-jobs", base_url: "https://elixirjobs.net", host: "elixirjobs.net", stacks: %w[elixir phoenix erlang] },
      { name: "GolangProjects", slug: "golang-projects", base_url: "https://www.golangprojects.com", host: "golangprojects.com", stacks: %w[go golang] },
      { name: "RustJobs.dev", slug: "rust-jobs-dev", base_url: "https://rustjobs.dev", host: "rustjobs.dev", stacks: %w[rust] },
      { name: "Kotlin Brasil", slug: "kotlin-brasil-jobs", base_url: "https://kotlin.dev.br/vagas", host: "kotlin.dev.br", stacks: %w[kotlin android java] },
      { name: "Mobile Career Swift", slug: "mobile-career-swift", base_url: "https://mobile.career/swift-developer-jobs", host: "mobile.career", stacks: %w[swift ios macos] },
      { name: "C++ Jobs", slug: "cpp-jobs", base_url: "https://cppjobs.it", host: "cppjobs.it", stacks: [ "c", "c++", "cpp" ] },
      { name: "EmbeddedJobs", slug: "embedded-jobs", base_url: "https://embedded.jobs/embedded-c%2B%2B-jobs", host: "embedded.jobs", stacks: [ "c", "c++", "cpp", "rust", "embedded" ] }
    ].freeze
    LANGUAGE_BOARD_DEFAULTS = LANGUAGE_BOARD_SPECS.map do |spec|
      path = URI.parse(spec.fetch(:base_url)).path.presence || "/"

      {
        name: spec.fetch(:name),
        slug: spec.fetch(:slug),
        source_kind: :platform,
        base_url: spec.fetch(:base_url),
        host: spec.fetch(:host),
        priority: 38,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LANGUAGE_BOARD_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ spec.fetch(:base_url) ],
          search_hosts: [ spec.fetch(:host) ],
          search_paths: [ path ],
          stack_terms: spec.fetch(:stacks),
          regions: %w[global remote],
          seed_queries: spec.fetch(:stacks).first(4).map { |stack| "#{stack} jobs remote" }
        }
      }
    end.freeze
    COMPANY_LIST_FALLBACK_REASON = "Planilha publica que lista empresas contratando, nao vagas; usar Codex fallback para extrair paginas de carreira, promover boards de ATS ja suportados para os settings da fonte nativa e so entao ingerir vagas.".freeze
    COMPANY_LIST_SPECS = [
      { name: "European Tech Companies Visa Sponsorship", slug: "list-european-visa-sponsorship", sheet_id: "13Q8-g51jan_e2ISx-yAFkXU2uW0SNR7G-TeoNYxPIBs", regions: %w[europe portugal remote] },
      { name: "Remotive Remote Startups", slug: "list-remotive-remote-startups", sheet_id: "18bljq3y5YTxPLmA4xj10EaKxs1KWhIdLTr8bF1K5XKI", regions: %w[global remote] },
      { name: "100% Remote Hiring Companies", slug: "list-remote-hiring-companies", sheet_id: "1CLTL5PoQ99tbxQ5qbj2ScxqbzS0ASr0Qm0b1wjOot9I", regions: %w[global remote] },
      { name: "Recently Funded Startups", slug: "list-recently-funded-startups", sheet_id: "1w11kuIGWOVATOad5acQqVWSzELF25xCyP6j3yoBiEUc", regions: %w[global remote] },
      { name: "Pragmatic Engineer Companies Hiring", slug: "list-pragmatic-engineer-hiring", sheet_id: "1_71AwBP4lv3yCBHjfbYbZ1gqNWMQht0JRPB6H7y9_Mg", regions: %w[global remote] }
    ].freeze
    COMPANY_LIST_DEFAULTS = COMPANY_LIST_SPECS.map do |spec|
      sheet_url = "https://docs.google.com/spreadsheets/d/#{spec.fetch(:sheet_id)}"

      {
        name: spec.fetch(:name),
        slug: spec.fetch(:slug),
        source_kind: :aggregator,
        base_url: "#{sheet_url}/htmlview",
        host: "docs.google.com",
        priority: 46,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: COMPANY_LIST_FALLBACK_REASON,
        scan_window_days: 30,
        settings: {
          seed_urls: [ "#{sheet_url}/htmlview" ],
          export_urls: [ "#{sheet_url}/export?format=csv", "#{sheet_url}/gviz/tq?tqx=out:csv" ],
          regions: spec.fetch(:regions),
          promotes_to: %w[greenhouse lever ashby smartrecruiters workable],
          seed_queries: [ "careers page", "open roles remote" ]
        }
      }
    end.freeze
    LATAM_SEED_QUERIES = [
      "senior software engineer remote latin america",
      "senior frontend engineer remote latam",
      "senior backend engineer remote latam",
      "full stack developer remote latin america",
      "react next.js developer remote latam",
      "ruby on rails developer remote latam",
      "technical recruiter remote latin america",
      "data analyst remote latam",
      "product manager remote latin america",
      "customer success remote latam"
    ].freeze

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
          company_slugs: %w[bkln blablacar bloomon cfsenergy ciandt contentsquare decilegroup enable fampay findigs fundrise gettyimages jobgether jupiterintel kasada koalahealth matchgroup octoenergy pigment planner5d prismic sonarsource toptal]
        }
      },
      {
        name: "Loxo - FitNext",
        slug: "loxo-fitnext",
        source_kind: :ats,
        base_url: "https://pod6.app.loxo.co/fitnext",
        host: "app.loxo.co",
        priority: 22,
        adapter_key: "loxo_job_board",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          board_urls: [ "https://pod6.app.loxo.co/fitnext" ],
          seed_urls: [
            "https://fitnext.app.loxo.co/job/NDI0NzQtOG1zMzg5NjhsN3NpeTNnYg=="
          ]
        }
      },
      {
        name: "Luflox",
        slug: "luflox",
        source_kind: :company,
        base_url: "https://www.luflox.com/career",
        host: "luflox.com",
        priority: 22,
        adapter_key: "luflox_positions",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          max_pages: 5,
          seed_urls: [
            "https://www.luflox.com/career/details/kWCKNjWHsbkWljOEbjBw"
          ]
        }
      },
      {
        name: "Nir Yu",
        slug: "nir-yu",
        source_kind: :company,
        base_url: "https://niryu.teamtailor.com",
        host: "niryu.teamtailor.com",
        priority: 22,
        adapter_key: "teamtailor_company_boards",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          board_urls: [ "https://niryu.teamtailor.com" ],
          max_pages: 6
        }
      },
      {
        name: "Prometeo Talent",
        slug: "prometeo-talent",
        source_kind: :platform,
        base_url: "https://jobs.prometeotalent.com",
        host: "jobs.prometeotalent.com",
        priority: 22,
        adapter_key: "teamtailor_company_boards",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          board_urls: [ "https://jobs.prometeotalent.com" ],
          max_pages: 6
        }
      },
      {
        name: "Blue Coding",
        slug: "blue-coding",
        source_kind: :platform,
        base_url: "https://jobs.lever.co/bluecoding",
        host: "jobs.lever.co",
        priority: 22,
        adapter_key: "lever_company_boards",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          company_slugs: [ "bluecoding" ]
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
          board_tokens: %w[airtable apolloio aquaticcapitalmanagement autoscout24 buzzfeed checkr clear codazen diligentrobotics enigmaio evolutioniq flexport fueledcareers goatgroup gocardless hightouch hippo70 mavenclinic nansen okx philo prisma rdsourcing sothebys spacex tide twilio]
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
          board_slugs: %w[clipboard footprint humaans lightdash ravio ruby-labs skydropx]
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
      { name: "Rails Job Board", slug: "rails-job-board", source_kind: :platform, base_url: "https://jobs.rubyonrails.org", host: "jobs.rubyonrails.org", priority: 18, adapter_key: "rails_jobs_rss", supports_backfill: true, scan_window_days: 20, settings: { feed_url: "https://jobs.rubyonrails.org/jobs.rss" } },
      { name: "RemoteOK", slug: "remoteok", source_kind: :platform, base_url: "https://remoteok.com", host: "remoteok.com", priority: 25, adapter_key: "remoteok_jobs_api", supports_backfill: true, scan_window_days: 20 },
      {
        name: "RemoteYeah",
        slug: "remoteyeah",
        source_kind: :platform,
        base_url: "https://remoteyeah.com",
        host: "remoteyeah.com",
        priority: 24,
        adapter_key: "remoteyeah_rss",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          feed_url: "https://remoteyeah.com/rss.xml",
          seed_urls: [
            "https://remoteyeah.com/jobs/remote-lead-ruby-on-rails-software-engineer-alex-staff-agency-4?utm_source=linkedin"
          ]
        }
      },
      {
        name: "RailsFullstack",
        slug: "railsfullstack",
        source_kind: :platform,
        base_url: "https://www.railsfullstack.com",
        host: "railsfullstack.com",
        priority: 24,
        adapter_key: "railsfullstack_jobs_sitemap",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          collection_urls: [
            "https://www.railsfullstack.com/collections/remote-full-stack-rails-jobs"
          ],
          sitemap_url: "https://www.railsfullstack.com/sitemap.xml",
          max_jobs: 40
        }
      },
      { name: "Remotive", slug: "remotive", source_kind: :platform, base_url: "https://remotive.com", host: "remotive.com", priority: 25, adapter_key: "remotive_remote_jobs", supports_backfill: true, scan_window_days: 20 },
      { name: "Himalayas", slug: "himalayas", source_kind: :platform, base_url: "https://himalayas.app", host: "himalayas.app", priority: 25, adapter_key: "himalayas_jobs_api", supports_backfill: true, scan_window_days: 20 },
      {
        name: "Artificial Intelligence Jobs",
        slug: "artificial-intelligence-jobs",
        source_kind: :aggregator,
        base_url: "https://artificialintelligencejobs.co/remote-ai-jobs",
        host: "artificialintelligencejobs.co",
        priority: 26,
        adapter_key: "artificialintelligencejobs_api",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          remote_only: true,
          page_size: 50,
          max_pages: 4,
          max_detail_pages: 12
        }
      },
      {
        name: "GoGloby",
        slug: "gogloby",
        source_kind: :platform,
        base_url: "https://gogloby.com/jobs/",
        host: "gogloby.com",
        priority: 24,
        adapter_key: "gogloby_jobs_sitemap",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          sitemap_url: "https://gogloby.com/jobs-sitemap.xml",
          max_jobs: 25
        }
      },
      {
        name: "GoGloby Notion",
        slug: "gogloby-notion",
        source_kind: :company,
        base_url: "https://gogloby.notion.site",
        host: "gogloby.notion.site",
        priority: 26,
        adapter_key: "notion_public_pages",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          company_name: "GoGloby",
          page_urls: [
            {
              url: "https://gogloby.notion.site/Senior-Full-Stack-Ruby-on-Rails-Developer-3ad2af3d743680ac8f29ec22df48b623",
              mirror_of: "https://gogloby.com/jobs/senior-full-stack-ruby-on-rails-developer"
            }
          ]
        }
      },
      {
        name: "We Work Remotely",
        slug: "weworkremotely",
        source_kind: :platform,
        base_url: "https://weworkremotely.com",
        host: "weworkremotely.com",
        priority: 24,
        adapter_key: "weworkremotely_rss",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          feed_urls: [
            "https://weworkremotely.com/categories/remote-programming-jobs.rss",
            "https://weworkremotely.com/categories/remote-full-stack-programming-jobs.rss",
            "https://weworkremotely.com/categories/remote-back-end-programming-jobs.rss",
            "https://weworkremotely.com/categories/remote-front-end-programming-jobs.rss"
          ]
        }
      },
      {
        name: "beBee",
        slug: "bebee",
        source_kind: :aggregator,
        base_url: "https://bebee.com/br/jobs",
        host: "bebee.com",
        priority: 25,
        adapter_key: "bebee_jobs_page",
        supports_backfill: true,
        scan_window_days: 20,
        settings: {
          search_queries: %w[ruby react],
          remote_filter: "full_remote"
        }
      },
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
          company_identifiers: %w[smartrecruiters ubisoft2]
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
        base_url: "https://englishjobs.pt",
        host: "englishjobs.pt",
        priority: 36,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "englishjobs.pt" ],
          search_paths: [ "/" ],
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
          seed_urls: [
            "https://www.workingnomads.com/remote-portugal-jobs",
            "https://www.workingnomads.com/remote-ruby-on-rails-jobs"
          ],
          search_hosts: [ "www.workingnomads.com", "workingnomads.com" ],
          search_paths: [ "/remote-portugal-jobs", "/remote-ruby-on-rails-jobs" ],
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
        base_url: "https://www.remoterocketship.com/country/portugal/jobs",
        host: "remoterocketship.com",
        priority: 41,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.remoterocketship.com", "remoterocketship.com" ],
          search_paths: [ "/country/portugal/jobs" ],
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
        base_url: "https://www.glassdoor.com/Job/portugal-jobs-SRCH_IL.0,8_IN195.htm",
        host: "glassdoor.com",
        priority: 43,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.glassdoor.com", "glassdoor.com" ],
          search_paths: [ "/Job/portugal-jobs-SRCH_IL.0,8_IN195.htm" ],
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
        base_url: "https://www.crossover.com/jobs/pt",
        host: "crossover.com",
        priority: 43,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.crossover.com", "crossover.com" ],
          search_paths: [ "/jobs/pt" ],
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
          seed_urls: [
            "https://arc.dev/en-pt/remote-jobs",
            "https://arc.dev/remote-jobs/ruby-on-rails"
          ],
          search_hosts: [ "arc.dev" ],
          search_paths: [ "/en-pt/remote-jobs", "/remote-jobs/ruby-on-rails" ],
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
        base_url: "https://startup.jobs/locations/lisbon",
        host: "startup.jobs",
        priority: 43,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "startup.jobs" ],
          search_paths: [ "/locations/lisbon" ],
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
          search_paths: [ "/empregos" ],
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
        base_url: "https://www.michaelpage.pt/jobs",
        host: "michaelpage.pt",
        priority: 44,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: PORTUGAL_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          search_hosts: [ "www.michaelpage.pt", "michaelpage.pt" ],
          search_paths: [ "/jobs" ],
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
        name: "DataAnnotation Coding",
        slug: "dataannotation-coding",
        source_kind: :platform,
        base_url: "https://www.dataannotation.tech/coding",
        host: "dataannotation.tech",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Plataforma de trabalho remoto em avaliacao e treinamento de IA; usar Codex fallback para confirmar disponibilidade regional, senioridade e termos antes da ingestao.",
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://www.dataannotation.tech/coding" ],
          search_hosts: [ "www.dataannotation.tech", "dataannotation.tech" ],
          search_paths: [ "/coding" ],
          regions: %w[global remote],
          seed_queries: [ "senior software engineer remote", "coding AI training remote" ]
        }
      },
      {
        name: "Proxify Careers",
        slug: "proxify-careers",
        source_kind: :platform,
        base_url: "https://career.proxify.io/ruby-on-rails/vacancies",
        host: "career.proxify.io",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Portal remoto especializado com protecao anti-bot para o worker Rails; usar Codex fallback e validar a vaga antes da ingestao.",
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://career.proxify.io/ruby-on-rails/vacancies" ],
          search_hosts: [ "career.proxify.io" ],
          search_paths: [ "/ruby-on-rails/vacancies" ],
          stack_terms: [ "ruby", "ruby on rails", "rails" ],
          regions: %w[global remote],
          seed_queries: [ "senior ruby on rails remote" ]
        }
      },
      {
        name: "RemoteJobsFinder",
        slug: "remote-jobs-finder",
        source_kind: :aggregator,
        base_url: "https://remotejobsfinder.co/en",
        host: "remotejobsfinder.co",
        priority: 42,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Agregador remoto sem adapter Rails validado; usar Codex fallback, checar recencia e preferir o ATS ou careers page original.",
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://remotejobsfinder.co/en" ],
          search_hosts: [ "remotejobsfinder.co", "www.remotejobsfinder.co" ],
          search_paths: [ "/en" ],
          regions: %w[global remote],
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "JobLeads Portugal",
        slug: "jobleads-portugal",
        source_kind: :aggregator,
        base_url: "https://www.jobleads.com/pt/jobs?filter_by_remote=remote",
        host: "jobleads.com",
        priority: 44,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Agregador com listagem remota de Portugal atras de desafio Cloudflare (503 em requisicoes repetidas) e sem link externo de candidatura; o payload publico traz sobretudo vagas antigas, entao usar Codex fallback para confirmar recencia e localizar o anuncio original antes da ingestao.",
        scan_window_days: 20,
        settings: {
          seed_urls: [
            "https://www.jobleads.com/pt/jobs?filter_by_remote=remote"
          ],
          search_hosts: [ "www.jobleads.com", "jobleads.com" ],
          search_paths: [ "/pt/jobs", "/pt/job" ],
          regions: [ "portugal", "remote" ],
          default_location: "Portugal",
          location_terms: PORTUGAL_LOCATION_TERMS,
          seed_queries: PORTUGAL_SEED_QUERIES
        }
      },
      {
        name: "Wellfound (AngelList Talent)",
        slug: "wellfound",
        source_kind: :platform,
        base_url: "https://wellfound.com/jobs",
        host: "wellfound.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Portal de startups (angel.co redireciona para wellfound.com) protegido por desafio Cloudflare para o worker Rails; usar Codex fallback, validar vaga ativa e preferir o ATS da startup quando existir.",
        scan_window_days: 20,
        settings: {
          seed_urls: [
            "https://wellfound.com/jobs",
            "https://wellfound.com/role/r/ruby-on-rails-developer",
            "https://wellfound.com/role/r/react-developer"
          ],
          search_hosts: [ "wellfound.com", "angel.co" ],
          search_paths: [ "/jobs", "/role/r/ruby-on-rails-developer", "/role/r/react-developer" ],
          regions: %w[global remote],
          seed_queries: [
            "senior ruby on rails engineer remote startup",
            "senior react engineer remote startup",
            "senior software engineer remote latam startup"
          ]
        }
      },
      {
        name: "Job Board Search",
        slug: "job-board-search",
        source_kind: :aggregator,
        base_url: "https://jobboardsearch.com",
        host: "jobboardsearch.com",
        priority: 45,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: "Diretorio de job boards, nao de vagas; usar Codex fallback para descobrir novos boards por stack e promover as fontes uteis ao catalogo, nunca para ingerir vagas direto.",
        scan_window_days: 30,
        settings: {
          seed_urls: [ "https://jobboardsearch.com" ],
          search_hosts: [ "jobboardsearch.com" ],
          search_paths: [ "/" ],
          regions: %w[global remote],
          seed_queries: [
            "ruby on rails job board",
            "react job board remote",
            "remote engineering job board latam"
          ]
        }
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
      },
      {
        name: "TurnKey Staffing",
        slug: "turnkey-staffing",
        source_kind: :company,
        base_url: "https://turnkeystaffing.com/career",
        host: "turnkeystaffing.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://turnkeystaffing.com/career/" ],
          search_hosts: [ "turnkeystaffing.com" ],
          search_paths: [ "/career/" ],
          regions: [ "latam", "remote" ],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "CloudDevs",
        slug: "clouddevs",
        source_kind: :platform,
        base_url: "https://clouddevs.com/jobs",
        host: "clouddevs.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://clouddevs.com/jobs/" ],
          search_hosts: [ "clouddevs.com" ],
          search_paths: [ "/jobs/", "/job/" ],
          regions: [ "latam", "remote" ],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "Hire With Near",
        slug: "hire-with-near",
        source_kind: :platform,
        base_url: "https://jobs.hirewithnear.com",
        host: "jobs.hirewithnear.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://jobs.hirewithnear.com/" ],
          search_hosts: [ "jobs.hirewithnear.com", "www.hirewithnear.com" ],
          search_paths: [ "/", "/job/" ],
          regions: [ "latam", "remote" ],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "weKnow",
        slug: "weknow",
        source_kind: :company,
        base_url: "https://weknowinc.com/careers/work-at-weknow",
        host: "weknowinc.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://weknowinc.com/careers/work-at-weknow/" ],
          search_hosts: [ "weknowinc.com" ],
          search_paths: [ "/careers/work-at-weknow/" ],
          regions: [ "latam", "remote" ],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "Revelo",
        slug: "revelo",
        source_kind: :platform,
        base_url: "https://careers.revelo.com",
        host: "careers.revelo.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [
            "https://careers.revelo.com/jobs/full-stack-developer",
            "https://careers.revelo.com/oportunidade/front-end-developer-remote-us-latam-sp-9000-200"
          ],
          search_hosts: [ "careers.revelo.com" ],
          search_paths: [ "/jobs/", "/vaga/", "/oportunidade/" ],
          regions: [ "latam", "remote" ],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "Awana",
        slug: "awana",
        source_kind: :platform,
        base_url: "https://www.awana.io/job-openings.html",
        host: "awana.io",
        priority: 41,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://www.awana.io/job-openings.html" ],
          search_hosts: [ "www.awana.io", "awana.io" ],
          search_paths: [ "/job-openings.html", "/latam-careers" ],
          regions: [ "latam", "remote" ],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "Tecla",
        slug: "tecla",
        source_kind: :platform,
        base_url: "https://www.tecla.io/join",
        host: "tecla.io",
        priority: 41,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://www.tecla.io/join", "https://app.tecla.io" ],
          search_hosts: [ "www.tecla.io", "app.tecla.io" ],
          search_paths: [ "/join", "/" ],
          regions: [ "latam", "remote" ],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "VanHack",
        slug: "vanhack",
        source_kind: :platform,
        base_url: "https://vanhack.com/get-hired",
        host: "vanhack.com",
        priority: 41,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://vanhack.com/get-hired", "https://app.vanhack.com" ],
          search_hosts: [ "vanhack.com", "app.vanhack.com" ],
          search_paths: [ "/get-hired", "/" ],
          regions: [ "latam", "remote" ],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "Kake",
        slug: "kake",
        source_kind: :company,
        base_url: "https://kake.co/jobs",
        host: "kake.co",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://kake.co/jobs" ],
          search_hosts: [ "kake.co" ],
          search_paths: [ "/jobs", "/jobs/" ],
          regions: %w[latam remote],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      },
      {
        name: "Zipdev",
        slug: "zipdev",
        source_kind: :company,
        base_url: "https://www.zipdev.com/careers",
        host: "zipdev.com",
        priority: 40,
        adapter_key: "manual_only",
        supports_backfill: false,
        codex_fallback_enabled: true,
        codex_fallback_reason: LATAM_FALLBACK_REASON,
        scan_window_days: 20,
        settings: {
          seed_urls: [ "https://www.zipdev.com/careers/" ],
          search_hosts: [ "www.zipdev.com", "zipdev.com" ],
          search_paths: [ "/careers/" ],
          regions: %w[latam remote],
          default_location: "Latin America",
          location_terms: LATAM_LOCATION_TERMS,
          seed_queries: LATAM_SEED_QUERIES
        }
      }
    ].concat(LANGUAGE_BOARD_DEFAULTS).concat(COMPANY_LIST_DEFAULTS).freeze

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
