require "test_helper"

class JobDiscovery::SearchIndex::BoardSeederTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 1, 1, 12)
  end

  teardown do
    travel_back
  end

  class FakeClient
    attr_reader :queries

    def initialize
      @queries = []
    end

    def enabled?
      true
    end

    def search(query, max_results:)
      @queries << [ query, max_results ]

      case query
      when /jobs\.recrutei\.com\.br/
        [ JobDiscovery::SearchIndex::Client::Result.new(url: "https://jobs.recrutei.com.br/acme/vacancy/123-desenvolvedora-react-senior") ]
      when /jobs\.lever\.co/
        [ JobDiscovery::SearchIndex::Client::Result.new(url: "https://jobs.lever.co/acme/123-senior-ruby") ]
      when /jobs\.ashbyhq\.com/
        [ JobDiscovery::SearchIndex::Client::Result.new(url: "https://jobs.ashbyhq.com/ruby-labs/abc") ]
      else
        []
      end
    end
  end

  class DisabledClient
    def enabled?
      false
    end
  end

  class ScriptedClient
    HOSTS = %w[jobs.eu.lever.co jobs.lever.co jobs.ashbyhq.com].freeze

    attr_reader :queries

    def self.host_for(query)
      HOSTS.find { |host| query.include?("site:#{host}") }
    end

    def initialize
      @queries = []
    end

    def enabled?
      true
    end

    def search(query, max_results:)
      @queries << [ query, max_results ]

      case self.class.host_for(query)
      when "jobs.eu.lever.co"
        raise "EU board unavailable"
      when "jobs.lever.co"
        [ "https://jobs.lever.co/acme/1", "https://jobs.lever.co/known/2", "https://jobs.lever.co/acme/3" ].map do |url|
          JobDiscovery::SearchIndex::Client::Result.new(url:)
        end
      when "jobs.ashbyhq.com"
        [ JobDiscovery::SearchIndex::Client::Result.new(url: "https://jobs.ashbyhq.com/ruby-labs/abc") ]
      else
        []
      end
    end
  end

  test "seeds adapter settings from search result urls" do
    JobSources::Catalog.seed!
    lever = JobSource.find_by!(slug: "lever")
    ashby = JobSource.find_by!(slug: "ashby")
    lever.update!(settings: { "company_slugs" => [ "known" ] })
    ashby.update!(settings: { "board_slugs" => [] })

    client = FakeClient.new
    result = JobDiscovery::SearchIndex::BoardSeeder.new(
      search_profiles: [ search_profiles(:default) ],
      sources: JobSource.where(slug: %w[lever ashby]),
      client:,
      max_queries: 2,
      results_per_query: 3
    ).call

    assert result.enabled
    assert_equal 2, result.query_count
    assert_equal 2, result.result_count
    assert_equal 2, result.seeded_count
    assert_includes lever.reload.settings["company_slugs"], "acme"
    assert_includes lever.settings["company_slugs"], "known"
    assert_includes ashby.reload.settings["board_slugs"], "ruby-labs"
    assert_equal 3, client.queries.first.last
  end

  test "is a no-op without configured search provider" do
    result = JobDiscovery::SearchIndex::BoardSeeder.new(
      search_profiles: [ search_profiles(:default) ],
      client: DisabledClient.new
    ).call

    assert_not result.enabled
    assert_equal 0, result.query_count
    assert_equal 0, result.seeded_count
    assert_equal [], result.queries
    assert_equal [], result.to_h[:queries]
  end

  test "reports one coverage entry per executed query within the query budget" do
    JobSources::Catalog.seed!

    result = JobDiscovery::SearchIndex::BoardSeeder.new(
      search_profiles: [ search_profiles(:default) ],
      sources: JobSource.where(slug: %w[lever ashby]),
      client: ScriptedClient.new,
      max_queries: 2,
      results_per_query: 3
    ).call

    assert_equal 2, result.query_count
    assert_equal 2, result.queries.size
    assert_equal 2, result.to_h[:queries].size
  end

  test "reports per-query coverage in execution order without query text" do
    JobSources::Catalog.seed!
    lever = JobSource.find_by!(slug: "lever")
    ashby = JobSource.find_by!(slug: "ashby")
    lever.update!(settings: { "company_slugs" => [ "known" ] })
    ashby.update!(settings: { "board_slugs" => [] })

    client = ScriptedClient.new
    result = JobDiscovery::SearchIndex::BoardSeeder.new(
      search_profiles: [ search_profiles(:default) ],
      sources: JobSource.where(slug: %w[lever ashby]),
      client:,
      max_queries: 12,
      results_per_query: 3
    ).call

    assert_equal 12, result.query_count
    assert_equal 12, result.queries.size
    assert_equal client.queries.map { |query, _| ScriptedClient.host_for(query) }, result.queries.map { |entry| entry[:host] }

    expected_keys = %i[host source_slug target_stack search_profile_ids result_count discovered_seed_count]
    result.queries.each do |entry|
      assert_equal expected_keys, entry.keys.without(:error)
      assert_equal entry[:host] == "jobs.eu.lever.co", entry.key?(:error)
    end
    client.queries.zip(result.queries).each do |(query, _), entry|
      assert_not_includes entry.to_s, query
      assert_not_includes entry.to_s, search_profiles(:default).name
    end

    eu_entries = result.queries.select { |entry| entry[:host] == "jobs.eu.lever.co" }
    assert_equal 4, eu_entries.size
    assert eu_entries.all? { |entry| entry[:error] == "RuntimeError" && entry[:result_count] == 0 && entry[:discovered_seed_count] == 0 }

    lever_entries = result.queries.select { |entry| entry[:host] == "jobs.lever.co" }
    ashby_entries = result.queries.select { |entry| entry[:host] == "jobs.ashbyhq.com" }
    assert_equal [ 1, 0, 0, 0 ], lever_entries.map { |entry| entry[:discovered_seed_count] }
    assert_equal [ 1, 0, 0, 0 ], ashby_entries.map { |entry| entry[:discovered_seed_count] }
    assert_equal [ 3, 3, 3, 3 ], lever_entries.map { |entry| entry[:result_count] }
    assert_equal [ 1, 1, 1, 1 ], ashby_entries.map { |entry| entry[:result_count] }

    assert_equal 16, result.result_count
    assert_equal result.result_count, result.queries.sum { |entry| entry[:result_count] }
    assert_equal 2, result.seeded_count
    assert_equal result.seeded_count, result.queries.sum { |entry| entry[:discovered_seed_count] }

    assert_equal 4, result.errors.size
    assert result.errors.all? { |error| error.start_with?("jobs.eu.lever.co: ") }
    assert_equal "jobs.eu.lever.co: EU board unavailable", result.errors.first

    assert_equal %w[known acme], lever.reload.settings["company_slugs"]
    assert_equal %w[ruby-labs], ashby.reload.settings["board_slugs"]
    assert_equal result.queries, result.to_h[:queries]
  end

  test "seeds Recrutei company labels from search results" do
    JobSources::Catalog.seed!
    recrutei = JobSource.find_by!(slug: "recrutei")
    recrutei.update!(settings: { "company_labels" => [ "known" ] })

    client = FakeClient.new
    result = JobDiscovery::SearchIndex::BoardSeeder.new(
      search_profiles: [ search_profiles(:default) ],
      sources: JobSource.where(slug: "recrutei"),
      client:,
      max_queries: 1,
      results_per_query: 3
    ).call

    assert result.enabled
    assert_equal 1, result.seeded_count
    assert_includes recrutei.reload.settings["company_labels"], "acme"
    assert_includes recrutei.settings["company_labels"], "known"
  end
end
