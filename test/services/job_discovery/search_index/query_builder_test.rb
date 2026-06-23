require "test_helper"

class JobDiscovery::SearchIndex::QueryBuilderTest < ActiveSupport::TestCase
  TARGETS = [
    { source_slug: "ashby", host: "jobs.ashbyhq.com", setting_key: "board_slugs" }
  ].freeze

  test "builds site queries from profile stack seniority and location terms" do
    query = JobDiscovery::SearchIndex::QueryBuilder.new(
      search_profiles: [ search_profiles(:default) ],
      targets: TARGETS
    ).queries(limit: 1).first

    assert_equal "ashby", query.source_slug
    assert_equal "jobs.ashbyhq.com", query.host
    assert_equal "ruby", query.target_stack
    assert_includes query.query, "site:jobs.ashbyhq.com"
    assert_includes query.query, '"senior ruby"'
    assert_includes query.query, '"remoto"'
    assert_includes query.query, '-"junior"'
  end

  test "respects portuguese-only title language" do
    profile = users(:one).search_profiles.create!(
      name: "Senior Salesforce BR",
      slug: "senior-salesforce-br-query-builder",
      active: true,
      language_scope: :portuguese,
      target_stacks: [ "salesforce" ],
      target_titles: [ "desenvolvedor", "engenheiro de software" ],
      seniority_terms: [ "senior" ],
      location_terms: [ "remoto" ],
      negative_terms: [],
      required_remote: true,
      include_women_only: false,
      scan_window_days: 20
    )

    query = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ profile ], targets: TARGETS).queries.first.query

    assert_includes query, '"desenvolvedor salesforce senior"'
    assert_not_includes query, "developer"
  end
end
