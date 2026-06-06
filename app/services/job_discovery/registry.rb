module JobDiscovery
  class Registry
    ADAPTERS = {
      "gupy_company_boards" => JobDiscovery::Adapters::GupyCompanyBoardsAdapter,
      "programathor_remote_senior" => JobDiscovery::Adapters::ProgramathorRemoteSeniorAdapter
    }.freeze

    def fetch(adapter_key)
      ADAPTERS.fetch(adapter_key)
    end

    def supports?(adapter_key)
      ADAPTERS.key?(adapter_key)
    end
  end
end
