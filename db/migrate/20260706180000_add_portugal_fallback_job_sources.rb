class AddPortugalFallbackJobSources < ActiveRecord::Migration[8.1]
  PORTUGAL_SOURCE_SLUGS = %w[
    itjobs-pt
    teamlyzer-jobs
    landing-jobs
    englishjobs-pt
    net-empregos-pt
    sapo-emprego
    expresso-emprego
    alerta-emprego
    eures
    eurotechjobs
    builtin-portugal
    working-nomads-portugal
    we-are-distributed-portugal
    remote-rocketship-portugal
    next-level-jobs-portugal
    wearedevelopers-portugal
    talent-com-portugal
    jobted-portugal
    jooble-portugal
    glassdoor-portugal
    crossover-portugal
    arc-portugal
    startup-jobs-lisbon
    randstad-portugal
    randstad-digital-portugal
    hays-portugal
    adecco-portugal
    michael-page-portugal
    robert-walters-portugal
    talent-portugal
  ].freeze

  def up
    JobSources::Catalog.seed!
    merge_search_hosts!("indeed", %w[br.indeed.com pt.indeed.com])
    merge_search_hosts!("linkedin", %w[www.linkedin.com br.linkedin.com pt.linkedin.com])
  end

  def down
    JobSource.where(slug: PORTUGAL_SOURCE_SLUGS).delete_all
    remove_search_hosts!("indeed", %w[pt.indeed.com])
    remove_search_hosts!("linkedin", %w[pt.linkedin.com])
  end

  private
    def merge_search_hosts!(slug, hosts)
      source = JobSource.find_by(slug:)
      return unless source

      settings = source.settings.to_h
      settings["search_hosts"] = (Array(settings["search_hosts"]).map(&:to_s) | hosts)
      source.update!(settings:)
    end

    def remove_search_hosts!(slug, hosts)
      source = JobSource.find_by(slug:)
      return unless source

      settings = source.settings.to_h
      settings["search_hosts"] = Array(settings["search_hosts"]).map(&:to_s) - hosts
      source.update!(settings:)
    end
end
