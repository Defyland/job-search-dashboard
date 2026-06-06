require "test_helper"

class JobDiscovery::Adapters::SmartrecruitersPostingsApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "discovers company identifiers from persisted smartrecruiters jobs and extracts strong matches" do
    source = JobSource.create!(
      name: "SmartRecruiters Test",
      slug: "smartrecruiters-test",
      host: "smartrecruiters.com",
      base_url: "https://jobs.smartrecruiters.com",
      source_kind: :ats,
      adapter_key: "smartrecruiters_postings_api",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "max_pages" => 1 }
    )
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Seed SmartRecruiters Job",
      company_name: "SmartRecruiters",
      apply_url: "https://jobs.smartrecruiters.com/smartrecruiters/744000109678592-frontend-web-developer",
      canonical_url: "https://jobs.smartrecruiters.com/smartrecruiters/744000109678592-frontend-web-developer",
      source_url: "https://jobs.smartrecruiters.com/smartrecruiters/744000109678592-frontend-web-developer",
      fingerprint: "seed::smartrecruiters::744000109678592",
      reason: "seed",
      score: 88,
      match_strength: :strong,
      seniority: "senior",
      remote_text: "Remote",
      location_text: "Brazil",
      stack_tags: [ "react" ]
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    postings_response = {
      "limit" => 100,
      "offset" => 0,
      "totalFound" => 1,
      "content" => [
        {
          "id" => "744000109678592",
          "name" => "Senior Frontend Engineer (React), Frontend Platform",
          "releasedDate" => 3.days.ago.iso8601,
          "location" => {
            "fullLocation" => "Brazil, REMOTE",
            "remote" => true
          },
          "ref" => "https://api.smartrecruiters.com/v1/companies/smartrecruiters/postings/744000109678592"
        }
      ]
    }.to_json

    detail_response = {
      "id" => "744000109678592",
      "uuid" => "34225731-e7cf-4584-b0b7-78098fe1a66b",
      "jobId" => "job-123",
      "jobAdId" => "jobad-456",
      "name" => "Senior Frontend Engineer (React), Frontend Platform",
      "releasedDate" => 3.days.ago.iso8601,
      "active" => true,
      "applyUrl" => "https://jobs.smartrecruiters.com/smartrecruiters/744000109678592-senior-frontend-engineer-frontend-platform?oga=true",
      "company" => { "name" => "SmartRecruiters", "identifier" => "smartrecruiters" },
      "department" => { "label" => "Engineering" },
      "experienceLevel" => { "label" => "Mid-Senior Level" },
      "location" => {
        "city" => "Brazil",
        "region" => "REMOTE",
        "country" => "br",
        "fullLocation" => "Brazil, REMOTE",
        "remote" => true,
        "hybrid" => false
      },
      "jobAd" => {
        "sections" => {
          "jobDescription" => { "text" => "React platform role for Brazil remote." },
          "qualifications" => { "text" => "Senior React engineer." }
        }
      }
    }.to_json

    adapter = JobDiscovery::Adapters::SmartrecruitersPostingsApiAdapter.new(
      fetcher: FakeFetcher.new(
        "https://api.smartrecruiters.com/v1/companies/smartrecruiters/postings?limit=100&offset=0" => postings_response,
        "https://api.smartrecruiters.com/v1/companies/smartrecruiters/postings/744000109678592" => detail_response
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "SmartRecruiters", candidates.first[:company_name]
    assert_equal "34225731-e7cf-4584-b0b7-78098fe1a66b", candidates.first[:external_job_id]
    assert_equal "https://jobs.smartrecruiters.com/smartrecruiters/744000109678592-senior-frontend-engineer-frontend-platform", candidates.first[:apply_url]
  end

  test "rejects stale or inactive smartrecruiters jobs" do
    source = JobSource.create!(
      name: "SmartRecruiters Manual",
      slug: "smartrecruiters-manual",
      host: "smartrecruiters.com",
      base_url: "https://jobs.smartrecruiters.com",
      source_kind: :ats,
      adapter_key: "smartrecruiters_postings_api",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "company_identifiers" => [ "smartrecruiters" ], "max_pages" => 1 }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    postings_response = {
      "limit" => 100,
      "offset" => 0,
      "totalFound" => 1,
      "content" => [
        {
          "id" => "744000000000001",
          "name" => "Senior Ruby Engineer",
          "releasedDate" => 40.days.ago.iso8601,
          "location" => {
            "fullLocation" => "Brazil, REMOTE",
            "remote" => true
          }
        }
      ]
    }.to_json

    adapter = JobDiscovery::Adapters::SmartrecruitersPostingsApiAdapter.new(
      fetcher: FakeFetcher.new(
        "https://api.smartrecruiters.com/v1/companies/smartrecruiters/postings?limit=100&offset=0" => postings_response
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_empty candidates
  end
end
