require "test_helper"

class JobSourceTest < ActiveSupport::TestCase
  test "seeds the default catalog idempotently" do
    missing_sources = JobSources::Catalog.defaults.count - JobSource.count

    assert_difference("JobSource.count", missing_sources) do
      JobSources::Catalog.seed!
    end

    assert_no_difference("JobSource.count") do
      JobSources::Catalog.seed!
    end
  end

  test "seed_defaults preserves operator overrides for existing sources" do
    source = job_sources(:gupy)
    source.update!(
      name: "Gupy Customizada",
      base_url: "https://custom.gupy.example",
      host: "custom.gupy.example",
      priority: 99,
      enabled: false,
      adapter_key: "manual_only",
      supports_backfill: false,
      scan_window_days: 7,
      settings: {
        "region" => "latam",
        "board_urls" => [ "https://custom.gupy.example/jobs" ]
      }
    )

    JobSources::Catalog.seed!
    source.reload

    assert_equal "Gupy Customizada", source.name
    assert_equal "https://custom.gupy.example", source.base_url
    assert_equal "custom.gupy.example", source.host
    assert_equal 99, source.priority
    assert_not source.enabled?
    assert_equal "manual_only", source.adapter_key
    assert_not source.supports_backfill?
    assert_equal 7, source.scan_window_days
    assert_equal(
      {
        "region" => "latam",
        "board_urls" => [ "https://custom.gupy.example/jobs" ]
      },
      source.settings
    )
  end

  test "seed_defaults only fills missing catalog fields for existing sources" do
    source = JobSource.create!(
      name: "Remotar",
      slug: "remotar",
      source_kind: :platform,
      base_url: nil,
      host: "remotar.com.br",
      priority: 77,
      enabled: true,
      adapter_key: "manual_only",
      supports_backfill: false,
      scan_window_days: 9,
      settings: {}
    )

    JobSources::Catalog.seed!
    source.reload

    assert_equal "https://remotar.com.br", source.base_url
    assert_equal 77, source.priority
    assert_equal "manual_only", source.adapter_key
    assert_not source.supports_backfill?
    assert_equal 9, source.scan_window_days
  end

  test "seed_defaults bootstraps curated adapter settings for blank existing sources" do
    JobSources::Catalog.seed!
    source = JobSource.find_by!(slug: "lever")
    quickin = JobSource.find_by!(slug: "quickin")
    recrutei = JobSource.find_by!(slug: "recrutei")
    smartrecruiters = JobSource.find_by!(slug: "smartrecruiters")

    source.update!(settings: {})
    quickin.update!(settings: {})
    recrutei.update!(settings: {})
    smartrecruiters.update!(settings: {})

    JobSources::Catalog.seed!
    source.reload
    quickin.reload
    recrutei.reload
    smartrecruiters.reload

    assert_equal %w[ciandt jobgether decilegroup toptal], source.settings["company_slugs"]
    assert_equal %w[evtit botcity reply qintess], quickin.settings["company_slugs"]
    assert_equal 6, quickin.settings["max_pages"]
    assert_equal [ "maxxi" ], recrutei.settings["company_labels"]
    assert_equal [ "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior" ], recrutei.settings["vacancy_urls"]
    assert_equal [ "smartrecruiters" ], smartrecruiters.settings["company_identifiers"]
  end

  test "default catalog marks blocked public sources for codex fallback" do
    JobSources::Catalog.seed!

    apinfo = JobSource.find_by!(slug: "apinfo")
    landor = JobSource.find_by!(slug: "landor-ats")
    linkedin = JobSource.find_by!(slug: "linkedin")
    icims = JobSource.find_by!(slug: "icims")
    jobvite = JobSource.find_by!(slug: "jobvite")
    workday = JobSource.find_by!(slug: "workday")
    bamboohr = JobSource.find_by!(slug: "bamboohr")
    jazzhr = JobSource.find_by!(slug: "jazzhr")
    netvagas = JobSource.find_by!(slug: "netvagas")
    remotely_works = JobSource.find_by!(slug: "remotely-works")
    rubyonremote = JobSource.find_by!(slug: "rubyonremote")
    get_great_careers = JobSource.find_by!(slug: "get-great-careers")
    indeed = JobSource.find_by!(slug: "indeed")

    assert apinfo.codex_fallback_enabled?
    assert_match "rate-limited", apinfo.codex_fallback_reason
    assert landor.codex_fallback_enabled?
    assert_match "Flutter", landor.codex_fallback_reason
    assert_equal [ "https://ats.landor.com.br/vaga-candidatura/51b51917-ffd9-4485-8239-8a986498d109" ], landor.settings["seed_urls"]
    assert linkedin.codex_fallback_enabled?
    assert_match "anti-bot", linkedin.codex_fallback_reason
    assert_equal [ "www.linkedin.com", "br.linkedin.com", "pt.linkedin.com" ], linkedin.settings["search_hosts"]
    assert icims.codex_fallback_enabled?
    assert_equal [ "careers.icims.com" ], icims.settings["search_hosts"]
    assert jobvite.codex_fallback_enabled?
    assert_equal [ "jobs.jobvite.com" ], jobvite.settings["search_hosts"]
    assert workday.codex_fallback_enabled?
    assert_equal [ "wd1.myworkdayjobs.com", "myworkdayjobs.com" ], workday.settings["search_hosts"]
    assert bamboohr.codex_fallback_enabled?
    assert_equal [ "jobs.bamboohr.com" ], bamboohr.settings["search_hosts"]
    assert jazzhr.codex_fallback_enabled?
    assert_equal [ "apply.jazz.co" ], jazzhr.settings["search_hosts"]
    assert netvagas.codex_fallback_enabled?
    assert_match "adapter curado", netvagas.codex_fallback_reason
    assert remotely_works.codex_fallback_enabled?
    assert_match "Turnstile", remotely_works.codex_fallback_reason
    assert rubyonremote.codex_fallback_enabled?
    assert_match "Cloudflare", rubyonremote.codex_fallback_reason
    assert get_great_careers.codex_fallback_enabled?
    assert_match "SPA orientada por query", get_great_careers.codex_fallback_reason
    assert indeed.codex_fallback_enabled?
    assert_match "Cloudflare", indeed.codex_fallback_reason
    assert_equal [ "br.indeed.com", "pt.indeed.com" ], indeed.settings["search_hosts"]
    assert_includes indeed.settings["seed_queries"], "tech recruiter remoto"
    assert_includes indeed.settings["seed_queries"], "marketing remoto"

    portugal_fallback_slugs = %w[
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
    ]

    portugal_fallback_slugs.each do |slug|
      source = JobSource.find_by!(slug:)

      assert source.codex_fallback_enabled?, "#{slug} should use codex fallback"
      assert_equal "manual_only", source.adapter_key
      assert_not source.supports_backfill?
      assert_match "Portugal", source.codex_fallback_reason
      assert_includes source.settings["regions"], "portugal"
      assert_includes source.settings["seed_queries"], "product manager portugal remote"
      assert_includes source.settings["seed_queries"], "sales portugal remote"
    end
  end

  test "seeds nearshore staffing and career sources" do
    JobSources::Catalog.seed!

    native_sources = {
      "prometeo-talent" => {
        adapter_key: "teamtailor_company_boards",
        settings_key: "board_urls",
        values: [ "https://jobs.prometeotalent.com" ],
        source_kind: "platform"
      },
      "blue-coding" => {
        adapter_key: "lever_company_boards",
        settings_key: "company_slugs",
        values: [ "bluecoding" ],
        source_kind: "platform"
      },
      "nir-yu" => {
        adapter_key: "teamtailor_company_boards",
        settings_key: "board_urls",
        values: [ "https://niryu.teamtailor.com" ],
        source_kind: "company"
      }
    }

    native_sources.each do |slug, config|
      source = JobSource.find_by!(slug:)

      assert source.supports_backfill?, "#{slug} should support native backfill"
      assert_equal config.fetch(:adapter_key), source.adapter_key
      assert_equal config.fetch(:source_kind), source.source_kind
      assert_equal config.fetch(:values), source.settings.fetch(config.fetch(:settings_key))
    end

    fallback_slugs = %w[
      turnkey-staffing
      clouddevs
      hire-with-near
      weknow
      revelo
      awana
      tecla
      vanhack
      kake
      zipdev
    ]

    fallback_slugs.each do |slug|
      source = JobSource.find_by!(slug:)

      assert_equal "manual_only", source.adapter_key
      assert_not source.supports_backfill?
      assert source.codex_fallback_enabled?
      assert_equal "Latin America", source.settings.fetch("default_location")
      assert_includes source.settings.fetch("seed_queries"), "senior software engineer remote latin america"
    end
  end

  test "seeds screenshot-sourced remote platforms" do
    JobSources::Catalog.seed!

    expected_urls = {
      "dataannotation-coding" => "https://www.dataannotation.tech/coding",
      "proxify-careers" => "https://career.proxify.io/ruby-on-rails/vacancies",
      "remote-jobs-finder" => "https://remotejobsfinder.co/en"
    }

    expected_urls.each do |slug, url|
      source = JobSource.find_by!(slug:)

      assert source.codex_fallback_enabled?
      assert_includes source.settings["seed_urls"], url
    end

    working_nomads = JobSource.find_by!(slug: "working-nomads-portugal")
    arc = JobSource.find_by!(slug: "arc-portugal")
    assert_includes working_nomads.settings["seed_urls"], "https://www.workingnomads.com/remote-ruby-on-rails-jobs"
    assert_includes arc.settings["seed_urls"], "https://arc.dev/remote-jobs/ruby-on-rails"
  end

  test "seeds native Rails, Loxo, Luflox, and RemoteYeah discovery sources" do
    JobSources::Catalog.seed!

    rails = JobSource.find_by!(slug: "rails-job-board")
    loxo = JobSource.find_by!(slug: "loxo-fitnext")
    luflox = JobSource.find_by!(slug: "luflox")
    remoteyeah = JobSource.find_by!(slug: "remoteyeah")
    railsfullstack = JobSource.find_by!(slug: "railsfullstack")

    assert rails.supports_backfill?
    assert_equal "rails_jobs_rss", rails.adapter_key
    assert_equal "https://jobs.rubyonrails.org/jobs.rss", rails.settings["feed_url"]

    assert loxo.supports_backfill?
    assert_equal "loxo_job_board", loxo.adapter_key
    assert_equal [ "https://pod6.app.loxo.co/fitnext" ], loxo.settings["board_urls"]
    assert_includes loxo.settings["seed_urls"], "https://fitnext.app.loxo.co/job/NDI0NzQtOG1zMzg5NjhsN3NpeTNnYg=="

    assert luflox.supports_backfill?
    assert_equal "luflox_positions", luflox.adapter_key
    assert_includes luflox.settings["seed_urls"], "https://www.luflox.com/career/details/kWCKNjWHsbkWljOEbjBw"

    assert remoteyeah.supports_backfill?
    assert_equal "remoteyeah_rss", remoteyeah.adapter_key
    assert_equal "https://remoteyeah.com/rss.xml", remoteyeah.settings["feed_url"]
    assert_includes remoteyeah.settings["seed_urls"], "https://remoteyeah.com/jobs/remote-lead-ruby-on-rails-software-engineer-alex-staff-agency-4?utm_source=linkedin"

    assert railsfullstack.supports_backfill?
    assert_equal "railsfullstack_jobs_sitemap", railsfullstack.adapter_key
    assert_equal [ "https://www.railsfullstack.com/collections/remote-full-stack-rails-jobs" ], railsfullstack.settings["collection_urls"]
    assert_equal "https://www.railsfullstack.com/sitemap.xml", railsfullstack.settings["sitemap_url"]
    assert_equal 40, railsfullstack.settings["max_jobs"]
  end

  test "seeds We Work Remotely natively and the Wellfound/Job Board Search assisted sources" do
    JobSources::Catalog.seed!

    wwr = JobSource.find_by!(slug: "weworkremotely")
    assert wwr.supports_backfill?
    assert_equal "weworkremotely_rss", wwr.adapter_key
    assert_equal "platform", wwr.source_kind
    assert_not wwr.codex_fallback_enabled?
    assert_includes wwr.settings["feed_urls"], "https://weworkremotely.com/categories/remote-programming-jobs.rss"
    assert wwr.settings["feed_urls"].all? { |url| url.start_with?("https://weworkremotely.com/") }

    wellfound = JobSource.find_by!(slug: "wellfound")
    assert wellfound.codex_fallback_enabled?
    assert_equal "manual_only", wellfound.adapter_key
    assert_not wellfound.supports_backfill?
    assert_includes wellfound.settings["seed_urls"], "https://wellfound.com/jobs"
    assert_includes wellfound.settings["search_hosts"], "angel.co"

    job_board_search = JobSource.find_by!(slug: "job-board-search")
    assert job_board_search.codex_fallback_enabled?
    assert_equal "manual_only", job_board_search.adapter_key
    assert_not job_board_search.supports_backfill?
    assert_includes job_board_search.settings["seed_urls"], "https://jobboardsearch.com"
    assert_match(/diretorio de job boards/i, job_board_search.codex_fallback_reason)
  end

  test "seeds stack-specific fallback job boards" do
    JobSources::Catalog.seed!

    JobSources::Catalog::LANGUAGE_BOARD_SPECS.each do |spec|
      source = JobSource.find_by!(slug: spec.fetch(:slug))

      assert source.codex_fallback_enabled?, "#{source.slug} should use Codex fallback"
      assert_equal "manual_only", source.adapter_key
      assert_not source.supports_backfill?
      assert_equal spec.fetch(:stacks), source.settings["stack_terms"]
      assert_equal [ spec.fetch(:base_url) ], source.settings["seed_urls"]
    end
  end

  test "general portugal fallbacks do not pin search paths to software-only categories" do
    JobSources::Catalog.seed!

    %w[
      englishjobs-pt
      remote-rocketship-portugal
      glassdoor-portugal
      crossover-portugal
      startup-jobs-lisbon
      randstad-portugal
      michael-page-portugal
    ].each do |slug|
      source = JobSource.find_by!(slug:)
      paths = Array(source.settings["search_paths"])

      refute paths.any? { |path| path.match?(/software|developer|full-stack|information-technology|programacao/) },
        "#{slug} should not default to tech-only search paths"
    end
  end

  test "backfillable sources require a supported adapter key" do
    source = JobSource.new(
      name: "Broken Source",
      slug: "broken-source",
      source_kind: :platform,
      base_url: "https://broken.example.com",
      host: "broken.example.com",
      priority: 10,
      enabled: true,
      adapter_key: "unsupported_adapter",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {}
    )

    assert_not source.valid?
    assert_includes source.errors[:adapter_key], "nao suporta backfill nativo"
  end
end
