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
    assert_includes indeed.settings["seed_queries"], "desenvolvedor ruby rails"
    assert_includes indeed.settings["seed_queries"], "ruby on rails portugal"

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
      assert_includes source.settings["seed_queries"], "ruby on rails portugal"
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
