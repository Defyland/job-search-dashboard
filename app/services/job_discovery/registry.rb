module JobDiscovery
  class Registry
    ADAPTERS = {
      "ashby_job_board" => JobDiscovery::Adapters::AshbyJobBoardAdapter,
      "coodesh_jobs_sitemap" => JobDiscovery::Adapters::CoodeshJobsSitemapAdapter,
      "gupy_company_boards" => JobDiscovery::Adapters::GupyCompanyBoardsAdapter,
      "greenhouse_boards_api" => JobDiscovery::Adapters::GreenhouseBoardsApiAdapter,
      "inhire_career_pages" => JobDiscovery::Adapters::InhireCareerPagesAdapter,
      "lever_company_boards" => JobDiscovery::Adapters::LeverCompanyBoardsAdapter,
      "programathor_remote_senior" => JobDiscovery::Adapters::ProgramathorRemoteSeniorAdapter,
      "recrutei_company_boards" => JobDiscovery::Adapters::RecruteiCompanyBoardsAdapter,
      "remotar_jobs_api" => JobDiscovery::Adapters::RemotarJobsApiAdapter,
      "solides_portal_vacancies" => JobDiscovery::Adapters::SolidesPortalVacanciesAdapter,
      "smartrecruiters_postings_api" => JobDiscovery::Adapters::SmartrecruitersPostingsApiAdapter,
      "teamtailor_company_boards" => JobDiscovery::Adapters::TeamtailorCompanyBoardsAdapter,
      "trampos_opportunities_api" => JobDiscovery::Adapters::TramposOpportunitiesApiAdapter,
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
