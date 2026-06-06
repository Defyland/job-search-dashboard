require "test_helper"

class JobSourceTest < ActiveSupport::TestCase
  test "seeds the default catalog idempotently" do
    missing_sources = JobSource::DEFAULT_CATALOG.count - JobSource.count

    assert_difference("JobSource.count", missing_sources) do
      JobSource.seed_defaults!
    end

    assert_no_difference("JobSource.count") do
      JobSource.seed_defaults!
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

    JobSource.seed_defaults!
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

    JobSource.seed_defaults!
    source.reload

    assert_equal "https://remotar.com.br", source.base_url
    assert_equal 77, source.priority
    assert_equal "manual_only", source.adapter_key
    assert_not source.supports_backfill?
    assert_equal 9, source.scan_window_days
  end

  test "seed_defaults bootstraps curated adapter settings for blank existing sources" do
    JobSource.seed_defaults!
    source = JobSource.find_by!(slug: "lever")
    recrutei = JobSource.find_by!(slug: "recrutei")
    smartrecruiters = JobSource.find_by!(slug: "smartrecruiters")

    source.update!(settings: {})
    recrutei.update!(settings: {})
    smartrecruiters.update!(settings: {})

    JobSource.seed_defaults!
    source.reload
    recrutei.reload
    smartrecruiters.reload

    assert_equal %w[ciandt jobgether decilegroup toptal], source.settings["company_slugs"]
    assert_equal [ "maxxi" ], recrutei.settings["company_labels"]
    assert_equal [ "https://jobs.recrutei.com.br/maxxi/vacancy/145107-desenvolvedora-front-end-reactnextjs-senior" ], recrutei.settings["vacancy_urls"]
    assert_equal [ "smartrecruiters" ], smartrecruiters.settings["company_identifiers"]
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
