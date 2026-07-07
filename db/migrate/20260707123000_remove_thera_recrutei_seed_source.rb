class RemoveTheraRecruteiSeedSource < ActiveRecord::Migration[8.1]
  THERA_COMPANY_LABEL = "thera-consulting".freeze
  THERA_VACANCY_URL = "https://jobs.recrutei.com.br/thera-consulting/vacancy/149473-desenvolvedora-frontend-senior".freeze

  def up
    source = JobSource.find_by(slug: "recrutei")
    return unless source

    settings = source.settings.to_h
    settings["company_labels"] = Array(settings["company_labels"]).map(&:to_s) - [ THERA_COMPANY_LABEL ]
    settings["vacancy_urls"] = Array(settings["vacancy_urls"]).map(&:to_s) - [ THERA_VACANCY_URL ]
    source.update!(settings:)
  end

  def down
  end
end
