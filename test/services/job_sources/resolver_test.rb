require "test_helper"

class JobSources::ResolverTest < ActiveSupport::TestCase
  test "resolves by slug before host fallback" do
    resolver = JobSources::Resolver.new(scope: JobSource.where(id: job_sources(:gupy).id))

    assert_equal job_sources(:gupy), resolver.resolve(name: "Outro nome", slug: "gupy", host: "clicksign.gupy.io")
  end

  test "resolves by host using the most specific source" do
    specific_source = JobSource.create!(
      name: "Clicksign",
      slug: "clicksign",
      source_kind: :company,
      base_url: "https://clicksign.gupy.io",
      host: "clicksign.gupy.io",
      priority: 5,
      enabled: true,
      adapter_key: "manual_only",
      supports_backfill: false,
      scan_window_days: 20,
      settings: {}
    )
    resolver = JobSources::Resolver.new(scope: JobSource.where(id: [ job_sources(:gupy).id, specific_source.id ]))

    assert_equal specific_source, resolver.resolve(name: nil, slug: nil, host: "clicksign.gupy.io")
  end

  test "register makes new sources immediately resolvable in the same run" do
    resolver = JobSources::Resolver.new(scope: JobSource.where(id: job_sources(:gupy).id))
    new_source = JobSource.new(
      name: "Race Careers",
      slug: "race-careers",
      source_kind: :company,
      base_url: "https://race.example",
      host: "race.example",
      priority: 50,
      enabled: true,
      adapter_key: "manual_only",
      supports_backfill: false,
      scan_window_days: 20,
      settings: {}
    )

    resolver.register(new_source)

    assert_equal new_source, resolver.resolve(name: "Race Careers", slug: "race-careers", host: "race.example")
  end
end
