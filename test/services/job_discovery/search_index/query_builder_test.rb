require "test_helper"

class JobDiscovery::SearchIndex::QueryBuilderTest < ActiveSupport::TestCase
  TARGETS = [
    { source_slug: "ashby", host: "jobs.ashbyhq.com", setting_key: "board_slugs" }
  ].freeze

  test "builds site queries from profile stack seniority and location terms" do
    query = JobDiscovery::SearchIndex::QueryBuilder.new(
      search_profiles: [ search_profiles(:default) ],
      targets: TARGETS
    ).queries(limit: 1, as_of: JobDiscovery::SearchIndex::QueryBuilder::ROTATION_EPOCH).first

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

    indeed_br = queries.find { |candidate| candidate.source_slug == "indeed" && candidate.host == "br.indeed.com" && candidate.target_stack == "ruby" }
    indeed_pt = queries.find { |candidate| candidate.source_slug == "indeed" && candidate.host == "pt.indeed.com" }
    itjobs = queries.find { |candidate| candidate.source_slug == "itjobs-pt" }
    recrutei = queries.find { |candidate| candidate.source_slug == "recrutei" && candidate.host == "jobs.recrutei.com.br" && candidate.target_stack == "ruby" }
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

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ profile ]).queries(as_of: JobDiscovery::SearchIndex::QueryBuilder::ROTATION_EPOCH)

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

    assert_equal queries.length, queries.map(&:query).uniq.length
    profiles.each do |profile|
      profile_stacks = queries.select { |query| query.search_profile_ids.include?(profile.id) }.map(&:target_stack).uniq
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

  test "spreads a limited budget across distinct profiles and hosts" do
    profiles = [
      query_profile(id: 910, location_terms: [ "remote" ]),
      query_profile(id: 911, location_terms: [ "remoto" ]),
      query_profile(id: 912, location_terms: [ "latam" ])
    ]
    targets = [
      { source_slug: "ashby", host: "jobs.ashbyhq.com", setting_key: nil },
      { source_slug: "lever", host: "jobs.lever.co", setting_key: nil },
      { source_slug: "greenhouse", host: "job-boards.greenhouse.io", setting_key: nil }
    ]

    smaller_budget = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: profiles, targets:).queries(limit: 2, as_of: JobDiscovery::SearchIndex::QueryBuilder::ROTATION_EPOCH)
    assert_equal [ 910, 911 ], smaller_budget.map(&:search_profile_id)
    assert_equal 2, smaller_budget.map(&:host).uniq.length

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: profiles, targets:).queries(limit: 3, as_of: JobDiscovery::SearchIndex::QueryBuilder::ROTATION_EPOCH)

    assert_equal 3, queries.length
    assert_equal [ 910, 911, 912 ], queries.map(&:search_profile_id).sort
    assert_operator queries.map(&:host).uniq.length, :>, 1
  end

  test "collapses equivalent profiles into one query that lists every profile" do
    profiles = [ query_profile(id: 920, name: "First"), query_profile(id: 921, name: "Second") ]

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: profiles, targets: TARGETS).queries

    assert_equal 1, queries.length
    assert_equal [ 920, 921 ], queries.first.search_profile_ids
    assert_equal 920, queries.first.search_profile_id
    assert_equal "First", queries.first.search_profile_name
    assert_equal [ 920, 921 ], queries.first.to_h[:search_profile_ids]
    assert_equal 920, queries.first.to_h[:search_profile_id]
  end

  test "never repeats a query string in a limited result" do
    profiles = [ query_profile(id: 930), query_profile(id: 931), query_profile(id: 932, location_terms: [ "latam" ]) ]

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: profiles, targets: TARGETS).queries(limit: 10, as_of: JobDiscovery::SearchIndex::QueryBuilder::ROTATION_EPOCH)

    assert_equal queries.map(&:query).uniq, queries.map(&:query)
  end

  test "keeps stack-specific boards on their own stack under a limited budget" do
    profile = query_profile(id: 940, stacks: [ "ruby", "python" ])
    targets = [
      { source_slug: "python", host: "python.org/jobs", setting_key: nil, stacks: %w[python django] },
      { source_slug: "general", host: "example.com/jobs", setting_key: nil }
    ]

    queries = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ profile ], targets:).queries(limit: 3, as_of: JobDiscovery::SearchIndex::QueryBuilder::ROTATION_EPOCH)

    assert queries.any?
    assert(queries.select { |query| query.source_slug == "python" }.all? { |query| query.target_stack == "python" })
  end

  test "treats limit zero as empty and nil as unlimited" do
    builder = JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: [ search_profiles(:default) ], targets: TARGETS)
    all_queries = builder.queries(limit: nil)

    assert_equal [], builder.queries(limit: 0)
    assert_operator all_queries.length, :>, 0
    assert_equal all_queries.map(&:query), builder.queries(limit: all_queries.length + 10).map(&:query)
  end

  # Each group is one profile with its own location, so every profile is a separate queue and
  # every query string is distinct. Groups and hosts form a full G x T grid.
  test "rotation keeps every daily window balanced and never repeats a query across rectangular shapes" do
    rotation_shapes.each do |groups, hosts|
      total = groups * hosts
      host_spread_limit = groups.gcd(hosts) == 1 ? 1 : 2

      (1...total).each do |budget|
        (0..(total.to_f / budget).ceil + total).each do |offset|
          queries = rotation_queries(groups, hosts, limit: budget, as_of: Date.new(2026, 3, 1) + offset)
          context = "groups=#{groups} hosts=#{hosts} budget=#{budget} offset=#{offset}"

          assert_equal queries.length, queries.map(&:query).uniq.length, context

          group_counts = (0...groups).map { |group| queries.count { |query| query.search_profile_id == rotation_profile_id(group) } }
          host_counts = (0...hosts).map { |host| queries.count { |query| query.host == rotation_host(host) } }

          assert_operator group_counts.max - group_counts.min, :<=, 1, context
          assert_operator host_counts.max - host_counts.min, :<=, host_spread_limit, context
        end
      end
    end
  end

  test "rotation covers every query within any run of consecutive days" do
    rotation_shapes.each do |groups, hosts|
      total = groups * hosts

      (1...total).each do |budget|
        days = (total.to_f / budget).ceil

        (0..total).each do |start_offset|
          pairs = (start_offset...(start_offset + days)).flat_map do |offset|
            rotation_queries(groups, hosts, limit: budget, as_of: Date.new(2026, 3, 1) + offset).map { |query| [ query.search_profile_id, query.host ] }
          end

          assert_equal total, pairs.uniq.length, "groups=#{groups} hosts=#{hosts} budget=#{budget} start_offset=#{start_offset}"
        end
      end
    end
  end

  test "rotation covers three groups over three hosts with a budget of four within three days" do
    windows = (0...3).map { |offset| rotation_queries(3, 3, limit: 4, as_of: Date.new(2026, 3, 1) + offset) }

    assert_equal 9, windows.flatten.map { |query| [ query.search_profile_id, query.host ] }.uniq.length

    windows.each do |window|
      host_counts = (0...3).map { |host| window.count { |query| query.host == rotation_host(host) } }

      # A budget-independent order cannot guarantee a host spread of one for every
      # window size. The approved bound for this non-coprime shape is two.
      assert_operator host_counts.max - host_counts.min, :<=, 2
    end
  end

  test "rotation is deterministic for a date and moves the window on the next day" do
    today = rotation_queries(3, 4, limit: 5, as_of: Date.new(2026, 6, 15)).map(&:query)

    assert_equal today, rotation_queries(3, 4, limit: 5, as_of: Date.new(2026, 6, 15)).map(&:query)
    refute_equal today, rotation_queries(3, 4, limit: 5, as_of: Date.new(2026, 6, 16)).map(&:query)
  end

  private
    def rotation_shapes
      [ [ 3, 4 ], [ 4, 3 ], [ 2, 5 ], [ 2, 3 ], [ 3, 3 ], [ 2, 4 ] ]
    end

    def rotation_profile_id(group)
      950 + group
    end

    def rotation_host(host)
      "host#{host}.example.com"
    end

    def rotation_queries(groups, hosts, limit:, as_of:)
      profiles = (0...groups).map { |group| query_profile(id: rotation_profile_id(group), location_terms: [ "region#{group}" ]) }
      targets = (0...hosts).map { |host| { source_slug: "general", host: rotation_host(host), setting_key: nil } }

      JobDiscovery::SearchIndex::QueryBuilder.new(search_profiles: profiles, targets:).queries(limit:, as_of:)
    end

    def query_profile(id:, name: "Profile #{id}", stacks: [ "ruby" ], location_terms: [ "remote" ])
      SearchProfile.new(
        id:,
        name:,
        language_scope: :both,
        target_stacks: stacks,
        target_titles: [ "developer", "engineer" ],
        seniority_terms: [ "senior" ],
        location_terms:,
        negative_terms: [],
        required_remote: true,
        include_women_only: false
      )
    end
end
