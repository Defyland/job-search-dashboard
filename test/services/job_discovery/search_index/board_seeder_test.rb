require "test_helper"

class JobDiscovery::SearchIndex::BoardSeederTest < ActiveSupport::TestCase
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
  end
end
