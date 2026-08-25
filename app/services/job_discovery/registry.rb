module JobDiscovery
  class Registry
    ADAPTERS = {
      "ashby_job_board" => JobDiscovery::Adapters::AshbyJobBoardAdapter,
      "bebee_jobs_page" => JobDiscovery::Adapters::BebeeJobsPageAdapter,
      "coodesh_jobs_sitemap" => JobDiscovery::Adapters::CoodeshJobsSitemapAdapter,
      "gupy_company_boards" => JobDiscovery::Adapters::GupyCompanyBoardsAdapter,
      "greenhouse_boards_api" => JobDiscovery::Adapters::GreenhouseBoardsApiAdapter,
      "gogloby_jobs_sitemap" => JobDiscovery::Adapters::GoglobyJobsSitemapAdapter,
      "himalayas_jobs_api" => JobDiscovery::Adapters::HimalayasJobsApiAdapter,
      "inhire_career_pages" => JobDiscovery::Adapters::InhireCareerPagesAdapter,
      "jobtarget_hosted_apply" => JobDiscovery::Adapters::JobtargetHostedApplyAdapter,
      "lever_company_boards" => JobDiscovery::Adapters::LeverCompanyBoardsAdapter,
      "loxo_job_board" => JobDiscovery::Adapters::LoxoJobBoardAdapter,
      "luflox_positions" => JobDiscovery::Adapters::LufloxPositionsAdapter,
      "programathor_remote_senior" => JobDiscovery::Adapters::ProgramathorRemoteSeniorAdapter,
      "quickin_company_boards" => JobDiscovery::Adapters::QuickinCompanyBoardsAdapter,
      "recrutei_company_boards" => JobDiscovery::Adapters::RecruteiCompanyBoardsAdapter,
      "remoteok_jobs_api" => JobDiscovery::Adapters::RemoteokJobsApiAdapter,
      "remoteyeah_rss" => JobDiscovery::Adapters::RemoteyeahRssAdapter,
      "railsfullstack_jobs_sitemap" => JobDiscovery::Adapters::RailsfullstackJobsSitemapAdapter,
      "remotive_remote_jobs" => JobDiscovery::Adapters::RemotiveRemoteJobsAdapter,
      "remotar_jobs_api" => JobDiscovery::Adapters::RemotarJobsApiAdapter,
      "rails_jobs_rss" => JobDiscovery::Adapters::RailsJobsRssAdapter,
      "solides_portal_vacancies" => JobDiscovery::Adapters::SolidesPortalVacanciesAdapter,
      "smartrecruiters_postings_api" => JobDiscovery::Adapters::SmartrecruitersPostingsApiAdapter,
      "teamtailor_company_boards" => JobDiscovery::Adapters::TeamtailorCompanyBoardsAdapter,
      "trampos_opportunities_api" => JobDiscovery::Adapters::TramposOpportunitiesApiAdapter,
      "weworkremotely_rss" => JobDiscovery::Adapters::WeworkremotelyRssAdapter,
      "workable_global_api" => JobDiscovery::Adapters::WorkableGlobalApiAdapter
    }.freeze

    def self.supported_adapter_keys
      ADAPTERS.keys
    end

    def self.supports?(adapter_key)
      ADAPTERS.key?(adapter_key)
    end

    def fetch(adapter_key)
      ADAPTERS.fetch(adapter_key)
    end

    def supports?(adapter_key)
      self.class.supports?(adapter_key)
    end
  end
end
