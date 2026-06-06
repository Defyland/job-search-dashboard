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
end
