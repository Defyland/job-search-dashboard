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
    recrutei = queries.find { |candidate| candidate.source_slug == "recrutei" && candidate.host == "jobs.recrutei.com.br" }
    teamlyzer = queries.find { |candidate| candidate.source_slug == "teamlyzer-jobs" }
    hays = queries.find { |candidate| candidate.source_slug == "hays-portugal" }
    remote_rocketship = queries.find { |candidate| candidate.source_slug == "remote-rocketship-portugal" }
    crossover = queries.find { |candidate| candidate.source_slug == "crossover-portugal" }
    michael_page = queries.find { |candidate| candidate.source_slug == "michael-page-portugal" }

    assert indeed_br
    assert_includes indeed_br.query, "site:br.indeed.com"
    assert_includes indeed_br.query, '"senior ruby"'
    assert indeed_pt
    assert_includes indeed_pt.query, "site:pt.indeed.com"
    assert recrutei
    assert_includes recrutei.query, "site:jobs.recrutei.com.br"
    assert_includes recrutei.query, '"desenvolvedora ruby senior"'
    assert itjobs
    assert_includes itjobs.query, "site:www.itjobs.pt"
    assert teamlyzer
    assert_includes teamlyzer.query, "site:pt.teamlyzer.com/companies/jobs"
    assert hays
    assert_includes hays.query, "site:www.hays.pt"
    assert remote_rocketship
    assert_includes remote_rocketship.query, "site:www.remoterocketship.com/country/portugal/jobs"
    assert_not_includes remote_rocketship.query, "software-engineer"
    assert crossover
    assert_includes crossover.query, "site:www.crossover.com/jobs/pt"
    assert_not_includes crossover.query, "full-stack-developer"
    assert michael_page
    assert_includes michael_page.query, "site:www.michaelpage.pt/jobs"
    assert_not_includes michael_page.query, "information-technology"
  end

  test "builds recruiter queries without software role phrases" do
    profile = users(:one).search_profiles.create!(
      name: "Senior Recruiter BR",
      slug: "senior-recruiter-br-query-builder",
      active: true,
      language_scope: :both,
      target_stacks: [ "recruiter" ],
      target_titles: SearchProfiles::Vocabulary.role_titles_for("both", target_stacks: [ "recruiter" ]),
      seniority_terms: [ "senior" ],
      location_terms: [ "remoto" ],
      negative_terms: [],
      required_remote: true,
      include_women_only: false,
      scan_window_days: 20
    )

    query = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ profile ], targets: TARGETS).queries.first.query

    assert_includes query, '"senior recruiter"'
    assert_includes query, '"senior tech recruiter"'
    assert_includes query, '"senior technical recruiter"'
    assert_not_includes query, "developer recruiter"
    assert_not_includes query, "software engineer recruiter"
  end

  test "only sends stack-specific queries to matching ecosystem boards" do
    targets = [
      { source_slug: "python", host: "python.org/jobs", setting_key: nil, stacks: %w[python django] },
      { source_slug: "rust", host: "rustjobs.dev", setting_key: nil, stacks: %w[rust] },
      { source_slug: "general", host: "example.com/jobs", setting_key: nil }
    ]
    profile = users(:one).search_profiles.create!(
      name: "Senior Python",
      slug: "senior-python-ecosystem-query",
      active: true,
      language_scope: :english,
      target_stacks: [ "python" ],
      target_titles: [ "developer", "engineer" ],
      seniority_terms: [ "senior" ],
      location_terms: [ "remote" ],
      negative_terms: [],
      required_remote: true,
      include_women_only: false,
      scan_window_days: 20
    )

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ profile ], targets:).queries

    assert_equal %w[python general], queries.map(&:source_slug)
    assert_includes queries.first.query, "site:python.org/jobs"
    refute queries.any? { |query| query.source_slug == "rust" }
  end

  test "builds final queries for every stack in a seven-stack profile" do
    stacks = [ "ruby", "ruby on rails", "react", "react native", "salesforce", "elixir", "golang" ]
    generated_titles = {
      "pt" => stacks.map { |stack| "desenvolvedor #{stack}" },
      "en" => stacks.map { |stack| "#{stack} developer" }
    }
    profile = SearchProfile.new(
      id: 901,
      name: "Seven-stack query profile",
      language_scope: :both,
      target_stacks: stacks,
      target_titles: [ "developer", "engineer" ],
      seniority_terms: [ "senior" ],
      location_terms: [ "remote" ],
      negative_terms: [],
      required_remote: true,
      include_women_only: false,
      settings: { "compiler" => { "generated_titles" => generated_titles } }
    )
    targets = [
      { source_slug: "general", host: "example.com", setting_key: nil },
      { source_slug: "elixir", host: "elixirjobs.net", setting_key: nil, stacks: %w[elixir phoenix] },
      { source_slug: "golang", host: "www.golangprojects.com", setting_key: nil, stacks: %w[go golang] }
    ]

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ profile ], targets:).queries
    query_stacks = queries.map(&:target_stack).uniq

    assert_equal stacks, query_stacks
    assert queries.any? { |query| query.target_stack == "elixir" && query.query.include?("\"senior phoenix\"") }
    assert queries.any? { |query| query.target_stack == "golang" && query.query.include?("\"senior go\"") }
  end

  test "interleaves a twelve-stack profile before applying the default global limit" do
    stacks = [ "ruby", "ruby on rails", "react", "react native", "salesforce", "elixir", "golang", "python", "java", "php", "node", "vue" ]
    profile = SearchProfile.new(
      id: 903,
      name: "Twelve-stack query profile",
      language_scope: :both,
      target_stacks: stacks,
      target_titles: [ "developer", "engineer" ],
      seniority_terms: [ "senior" ],
      location_terms: [ "remote" ],
      negative_terms: [],
      required_remote: true,
      include_women_only: false
    )

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ profile ]).queries

    assert_operator queries.length, :>=, 600
    assert_equal stacks.sort, queries.map(&:target_stack).uniq.sort
  end

  test "interleaves stacks across profiles before applying the default global limit" do
    stacks = [ "ruby", "ruby on rails", "react", "react native", "salesforce", "elixir", "golang" ]
    profiles = [ 904, 905 ].map do |id|
      SearchProfile.new(
        id:,
        name: "Seven-stack query profile #{id}",
        language_scope: :both,
        target_stacks: stacks,
        target_titles: [ "developer", "engineer" ],
        seniority_terms: [ "senior" ],
        location_terms: [ "remote" ],
        negative_terms: [],
        required_remote: true,
        include_women_only: false
      )
    end

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: profiles).queries

    assert_operator queries.length, :>=, 600
    profiles.each do |profile|
      profile_stacks = queries.select { |query| query.search_profile_id == profile.id }.map(&:target_stack).uniq
      assert_equal stacks.sort, profile_stacks.sort
    end
  end

  test "keeps Ruby and React queries isolated and retains seniority phrases" do
    stacks = [ "ruby", "ruby on rails", "react", "react native" ]
    profile = SearchProfile.new(
      id: 902,
      name: "Ruby Rails React query profile",
      language_scope: :both,
      target_stacks: stacks,
      target_titles: [ "developer", "engineer" ],
      seniority_terms: [ "senior" ],
      location_terms: [ "remote" ],
      negative_terms: [],
      required_remote: true,
      include_women_only: false,
      settings: {
        "compiler" => {
          "generated_titles" => {
            "pt" => [ "desenvolvedor ruby", "desenvolvedor ruby on rails", "desenvolvedor react", "desenvolvedor react native" ],
            "en" => [ "ruby developer", "ruby on rails developer", "react developer", "react native developer" ]
          }
        }
      }
    )

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(
      search_profiles: [ profile ],
      targets: [ { source_slug: "general", host: "example.com", setting_key: nil } ]
    ).queries
    ruby_query = queries.find { |query| query.target_stack == "ruby" }.query
    rails_query = queries.find { |query| query.target_stack == "ruby on rails" }.query
    react_query = queries.find { |query| query.target_stack == "react" }.query

    assert_includes ruby_query, '"senior ruby"'
    refute_includes ruby_query, '"desenvolvedor ruby on rails"'
    refute_includes ruby_query, '"ruby on rails developer"'
    assert_includes rails_query, '"desenvolvedor ruby on rails"'
    assert_includes rails_query, '"senior ruby on rails"'
    assert_includes react_query, '"senior react"'
    refute_includes react_query, '"desenvolvedor react native"'
  end

  test "regional ATS hosts are seeded alongside their primary hosts" do
    hosts = JobDiscovery::SearchIndex::QueryBuilder::TARGETS.map { |target| target[:host] }

    assert_includes hosts, "boards.eu.greenhouse.io"
    assert_includes hosts, "job-boards.eu.greenhouse.io"
    assert_includes hosts, "jobs.eu.lever.co"
  end
end
