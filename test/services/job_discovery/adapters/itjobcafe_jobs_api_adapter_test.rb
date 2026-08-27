require "test_helper"

class JobDiscovery::Adapters::ItjobcafeJobsApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(url, body:, headers: {})
      @requests << [ url, JSON.parse(body) ]
      @responses.fetch(JSON.parse(body).fetch("keywords"))
    end

    def call(url, limit: 5, headers: {}, allowed_hosts: nil)
      raise "unexpected GET: #{url}"
    end
  end

  def build_source_scan(settings)
    source = JobSource.create!(
      name: "ITJobCafe Test",
      slug: "itjobcafe-test",
      host: "itjobcafe.com",
      base_url: "https://www.itjobcafe.com/JobSearch/RemoteJobs",
      source_kind: :aggregator,
      adapter_key: "itjobcafe_jobs_api",
      supports_backfill: true,
      scan_window_days: 20,
      settings:
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
  end

  def job_row(id:, title:, posted_on: "7 Hours ago", company: "Clearance Jobs")
    {
      "ID" => id,
      "Title" => title,
      "Company" => company,
      "BriefInfo" => "Build Rails services and RESTful APIs with Sidekiq.",
      "City" => "Baltimore",
      "State" => "Maryland",
      "Url" => "/Jobprocess/jobdetail?id=#{id}&utm_source=jobfront",
      "PostedOn" => posted_on
    }
  end

  test "builds candidates from the public listing endpoint without fetching detail pages" do
    source_scan = build_source_scan("search_queries" => [ "ruby" ])
    fetcher = FakeFetcher.new(
      "ruby" => [
        job_row(id: "082706-AAA-01", title: "Senior Ruby on Rails Engineer"),
        job_row(id: "082706-BBB-02", title: "Recruiter", company: "Staffing Co")
      ].to_json
    )

    candidates = JobDiscovery::Adapters::ItjobcafeJobsApiAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    candidate = candidates.first
    assert_equal "Senior Ruby on Rails Engineer", candidate[:title]
    assert_equal "Clearance Jobs", candidate[:company_name]
    assert_equal "https://www.itjobcafe.com/Jobprocess/jobdetail?id=082706-AAA-01", candidate[:canonical_url]
    assert_equal "https://www.itjobcafe.com/JobProcess/GetMyJob1/082706-AAA-01", candidate[:apply_url]
    assert_equal "Baltimore, Maryland", candidate[:location_text]
    assert_equal [ [ "https://www.itjobcafe.com/JobSearch/GetLatestJobs", { "keywords" => "ruby", "location" => "" } ] ], fetcher.requests
    assert_equal 2, source_scan.reload.metadata["api_rows_seen"]
    assert_equal 1, source_scan.metadata["candidates_built"]
  end

  test "dedupes rows repeated across queries and drops rows older than the window" do
    source_scan = build_source_scan("search_queries" => [ "ruby", "rails" ])
    shared = job_row(id: "082706-AAA-01", title: "Senior Ruby on Rails Engineer")
    fetcher = FakeFetcher.new(
      "ruby" => [ shared, job_row(id: "082706-OLD-03", title: "Ruby Engineer", posted_on: "45 Days ago") ].to_json,
      "rails" => [ shared ].to_json
    )

    candidates = JobDiscovery::Adapters::ItjobcafeJobsApiAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal [ "082706-AAA-01" ], candidates.map { |candidate| candidate[:external_job_id] }
    assert_equal 2, fetcher.requests.size
    assert_equal 3, source_scan.reload.metadata["api_rows_seen"]
  end

  test "a malformed payload for one query does not abort the remaining queries" do
    source_scan = build_source_scan("search_queries" => [ "ruby", "rails" ])
    fetcher = FakeFetcher.new(
      "ruby" => "<html>not json</html>",
      "rails" => [ job_row(id: "082706-CCC-04", title: "Senior Ruby on Rails Developer") ].to_json
    )

    candidates = JobDiscovery::Adapters::ItjobcafeJobsApiAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal [ "082706-CCC-04" ], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "flags remote roles from the title because the listing has no remote field" do
    source_scan = build_source_scan("search_queries" => [ "ruby" ])
    fetcher = FakeFetcher.new(
      "ruby" => [ job_row(id: "082706-DDD-05", title: "Senior Rails Engineer - Remote / Telecommute") ].to_json
    )

    candidates = JobDiscovery::Adapters::ItjobcafeJobsApiAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal "Remote", candidates.first[:remote_text]
  end

  test "caps the number of configured queries" do
    source_scan = build_source_scan("search_queries" => (1..12).map { |index| "query#{index}" })
    responses = (1..12).to_h { |index| [ "query#{index}", [].to_json ] }
    fetcher = FakeFetcher.new(responses)

    JobDiscovery::Adapters::ItjobcafeJobsApiAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal JobDiscovery::Adapters::ItjobcafeJobsApiAdapter::MAX_QUERIES, fetcher.requests.size
  end
end
