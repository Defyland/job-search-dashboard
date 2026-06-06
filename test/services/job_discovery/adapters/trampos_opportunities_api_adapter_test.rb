require "test_helper"

class JobDiscovery::Adapters::TramposOpportunitiesApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "uses canonical detail page when trampos handles the application internally" do
    source = JobSource.create!(
      name: "Trampos Test",
      slug: "trampos-test",
      host: "trampos.co",
      base_url: "https://trampos.co",
      source_kind: :platform,
      adapter_key: "trampos_opportunities_api",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "max_pages" => 1 }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    listing_response = {
      "opportunities" => [
        {
          "id" => 773400,
          "name" => "Senior Ruby on Rails Developer",
          "published_at" => 2.days.ago.iso8601,
          "company" => { "name" => "Trampos Labs" }
        },
        {
          "id" => 773401,
          "name" => "Designer Sênior",
          "published_at" => 2.days.ago.iso8601,
          "company" => { "name" => "Example" }
        }
      ],
      "pagination" => { "total" => 2, "total_pages" => 1, "per_page" => 12 }
    }.to_json

    detail_response = {
      "opportunity" => {
        "id" => 773400,
        "name" => "Senior Ruby on Rails Developer",
        "apply_method" => 3,
        "apply_url" => "",
        "url" => "http://trampos.co/oportunidades/773400-senior-ruby-on-rails-developer",
        "type_slug" => "emprego",
        "category_slug" => "ti",
        "home_office" => true,
        "hybrid" => false,
        "city" => "Sao Paulo",
        "state" => "SP",
        "published_at" => 2.days.ago.iso8601,
        "description" => "Hands-on Ruby on Rails role for product engineering.",
        "prerequisite" => "Senior backend experience.",
        "desirable" => "React familiarity is a plus.",
        "other_info" => "",
        "comments" => "",
        "company" => { "name" => "Trampos Labs", "slug" => "trampos-labs" }
      }
    }.to_json

    adapter = JobDiscovery::Adapters::TramposOpportunitiesApiAdapter.new(
      fetcher: FakeFetcher.new(
        "https://trampos.co/api/v2/opportunities?page=1" => listing_response,
        "https://trampos.co/api/v2/opportunities/773400" => detail_response
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "https://trampos.co/oportunidades/773400-senior-ruby-on-rails-developer", candidates.first[:apply_url]
    assert_equal "https://trampos.co/oportunidades/773400-senior-ruby-on-rails-developer", candidates.first[:canonical_url]
    assert_equal "Trampos Labs", candidates.first[:company_name]
  end

  test "stops after stale pages and ignores jobs outside the window" do
    source = JobSource.create!(
      name: "Trampos Stale",
      slug: "trampos-stale",
      host: "trampos.co",
      base_url: "https://trampos.co",
      source_kind: :platform,
      adapter_key: "trampos_opportunities_api",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "max_pages" => 3 }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    listing_response = {
      "opportunities" => [
        {
          "id" => 700001,
          "name" => "Senior React Engineer",
          "published_at" => 35.days.ago.iso8601,
          "company" => { "name" => "Old Company" }
        }
      ],
      "pagination" => { "total" => 1, "total_pages" => 2, "per_page" => 12 }
    }.to_json

    adapter = JobDiscovery::Adapters::TramposOpportunitiesApiAdapter.new(
      fetcher: FakeFetcher.new(
        "https://trampos.co/api/v2/opportunities?page=1" => listing_response
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_empty candidates
    assert_equal 1, source_scan.pages_scanned
  end
end
