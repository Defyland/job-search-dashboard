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
    assert_includes query, '"desenvolvedora salesforce senior"'
    assert_includes query, '"frontend salesforce senior"'
    assert_not_includes query, "developer"
  end

  test "includes feminine and neutral role variants for bilingual searches" do
    profile = users(:one).search_profiles.create!(
      name: "Senior React BR",
      slug: "senior-react-br-query-builder",
      active: true,
      language_scope: :both,
      target_stacks: [ "react" ],
      target_titles: [ "desenvolvedor", "developer", "frontend" ],
      seniority_terms: [ "senior" ],
      location_terms: [ "remoto" ],
      negative_terms: [],
      required_remote: true,
      include_women_only: false,
      scan_window_days: 20
    )

    query = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ profile ], targets: TARGETS).queries.first.query

    assert_includes query, '"desenvolvedora react senior"'
    assert_includes query, '"engenheira de software react senior"'
    assert_includes query, '"frontend react senior"'
    assert_includes query, '"developer react senior"'
  end

  test "includes portugal fallback search targets" do
    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ search_profiles(:default) ]).queries

    indeed_br = queries.find { |candidate| candidate.source_slug == "indeed" && candidate.host == "br.indeed.com" }
    indeed_pt = queries.find { |candidate| candidate.source_slug == "indeed" && candidate.host == "pt.indeed.com" }
    itjobs = queries.find { |candidate| candidate.source_slug == "itjobs-pt" }
    teamlyzer = queries.find { |candidate| candidate.source_slug == "teamlyzer-jobs" }
    hays = queries.find { |candidate| candidate.source_slug == "hays-portugal" }

    assert indeed_br
    assert_includes indeed_br.query, "site:br.indeed.com"
    assert_includes indeed_br.query, '"senior ruby"'
    assert indeed_pt
    assert_includes indeed_pt.query, "site:pt.indeed.com"
    assert itjobs
    assert_includes itjobs.query, "site:www.itjobs.pt"
    assert teamlyzer
    assert_includes teamlyzer.query, "site:pt.teamlyzer.com/companies/jobs"
    assert hays
    assert_includes hays.query, "site:www.hays.pt"
  end
end
