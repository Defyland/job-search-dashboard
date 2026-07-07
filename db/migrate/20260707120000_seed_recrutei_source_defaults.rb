class SeedRecruteiSourceDefaults < ActiveRecord::Migration[8.1]
  MAXXI_VACANCY_URL = "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior".freeze

  def up
    JobSources::Catalog.seed!
    source = JobSource.find_by(slug: "recrutei")
    return unless source

    settings = source.settings.to_h
    settings["company_labels"] = (Array(settings["company_labels"]).map(&:to_s) | [ "maxxi" ])
    settings["vacancy_urls"] = (Array(settings["vacancy_urls"]).map(&:to_s) | [ MAXXI_VACANCY_URL ])
    source.update!(settings:)
  end

  def down
  end
end
