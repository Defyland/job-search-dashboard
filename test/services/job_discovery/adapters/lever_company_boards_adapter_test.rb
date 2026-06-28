require "test_helper"

class JobDiscovery::Adapters::LeverCompanyBoardsAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5)
      @responses.fetch(url)
    end
  end

  test "discovers company slugs from persisted lever jobs and extracts strong matches" do
    source = JobSource.create!(
      name: "Lever Test",
      slug: "lever-test",
      host: "jobs.lever.co",
      base_url: "https://jobs.lever.co",
      source_kind: :ats,
      adapter_key: "lever_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {}
    )
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Seed Lever Job",
      company_name: "CI&T",
      apply_url: "https://jobs.lever.co/ciandt/a1baffc5-29e1-42bd-a34c-d231ae9416d7",
      canonical_url: "https://jobs.lever.co/ciandt/a1baffc5-29e1-42bd-a34c-d231ae9416d7",
      source_url: "https://jobs.lever.co/ciandt/a1baffc5-29e1-42bd-a34c-d231ae9416d7",
      fingerprint: "seed::lever::ciandt",
      remote_text: "Remote",
      location_text: "Brazil"
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    created_at_ms = 1.day.ago.to_i * 1000

    response_body = [
      {
        "id" => "a1baffc5-29e1-42bd-a34c-d231ae9416d7",
        "text" => "[Job-29313] Senior Fullstack (React/Node) Developer, Brazil",
        "descriptionPlain" => "Remote role for Brazil with React and Node",
        "descriptionBodyPlain" => "React in title and backend collaboration",
        "createdAt" => created_at_ms,
        "hostedUrl" => "https://jobs.lever.co/ciandt/a1baffc5-29e1-42bd-a34c-d231ae9416d7",
        "applyUrl" => "https://jobs.lever.co/ciandt/a1baffc5-29e1-42bd-a34c-d231ae9416d7/apply",
        "workplaceType" => "remote",
        "categories" => {
          "commitment" => "Homeoffice",
          "location" => "Brazil",
          "allLocations" => [ "Brazil" ]
        }
      },
      {
        "id" => "other",
        "text" => "Product Designer",
        "descriptionPlain" => "Hybrid in Portugal",
        "createdAt" => created_at_ms,
        "hostedUrl" => "https://jobs.lever.co/ciandt/other",
        "applyUrl" => "https://jobs.lever.co/ciandt/other/apply",
        "workplaceType" => "hybrid",
        "categories" => {
          "location" => "Portugal"
        }
      }
    ].to_json

    adapter = JobDiscovery::Adapters::LeverCompanyBoardsAdapter.new(
      fetcher: FakeFetcher.new("https://api.lever.co/v0/postings/ciandt?mode=json" => response_body)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "CI&T", candidates.first[:company_name]
    assert_equal "a1baffc5-29e1-42bd-a34c-d231ae9416d7", candidates.first[:external_job_id]
  end

  test "skips generic senior roles with no target stack signal but keeps borderline matches with stack in context" do
    source = JobSource.create!(
      name: "Lever Noise Test",
      slug: "lever-noise-test",
      host: "jobs.lever.co",
      base_url: "https://jobs.lever.co",
      source_kind: :ats,
      adapter_key: "lever_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "company_slugs" => [ "jobgether" ] }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    created_at_ms = 1.day.ago.to_i * 1000

    response_body = [
      {
        "id" => "generic-java",
        "text" => "Senior Backend Engineer",
        "descriptionPlain" => "Java and Kafka for a core backend platform",
        "createdAt" => created_at_ms,
        "hostedUrl" => "https://jobs.lever.co/jobgether/generic-java",
        "applyUrl" => "https://jobs.lever.co/jobgether/generic-java/apply",
        "workplaceType" => "remote",
        "categories" => {
          "commitment" => "Full-time",
          "location" => "Brazil",
          "allLocations" => [ "Brazil" ]
        }
      },
      {
        "id" => "borderline-react",
        "text" => "Senior Fullstack Developer",
        "descriptionPlain" => "Remote role focused on React and frontend collaboration",
        "createdAt" => created_at_ms,
        "hostedUrl" => "https://jobs.lever.co/jobgether/borderline-react",
        "applyUrl" => "https://jobs.lever.co/jobgether/borderline-react/apply",
        "workplaceType" => "remote",
        "categories" => {
          "commitment" => "Full-time",
          "location" => "Brazil",
          "allLocations" => [ "Brazil" ]
        }
      }
    ].to_json

    adapter = JobDiscovery::Adapters::LeverCompanyBoardsAdapter.new(
      fetcher: FakeFetcher.new("https://api.lever.co/v0/postings/jobgether?mode=json" => response_body)
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "borderline", candidates.first[:classification]
    assert_equal "borderline-react", candidates.first[:external_job_id]
  end
end
