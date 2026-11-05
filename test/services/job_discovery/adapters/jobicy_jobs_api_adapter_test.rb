require "test_helper"

class JobDiscovery::Adapters::JobicyJobsApiAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :urls

    def initialize(*bodies)
      @bodies = bodies
      @urls = []
    end

    def call(url, limit: 5)
      @urls << url
      raise "unexpected request: #{url}" if @bodies.empty?

      @bodies.shift
    end
  end

  test "follows the opaque nextCursor with the same filters and stops when it is null" do
    source_scan = build_source_scan
    cursor = "AgAAAABq7NRd+opaque/Cursor=="
    fetcher = FakeFetcher.new(
      page_body(jobs: [ job(id: 1) ], next_cursor: cursor),
      page_body(jobs: [ job(id: 2) ], next_cursor: nil)
    )

    candidates = adapter(fetcher).scan(source_scan:, window_days: 20)

    assert_equal 2, fetcher.urls.size
    first_query = URI.decode_www_form(URI.parse(fetcher.urls.first).query).to_h
    second_query = URI.decode_www_form(URI.parse(fetcher.urls.second).query).to_h
    assert_equal "brazil", first_query["geo"]
    assert_equal "100", first_query["count"]
    assert_nil first_query["cursor"]
    assert_equal cursor, second_query["cursor"]
    assert_equal "brazil", second_query["geo"]
    assert_equal "100", second_query["count"]
    assert_equal %w[1 2], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "stops at max_pages even while nextCursor keeps coming" do
    source_scan = build_source_scan(settings: { "max_pages" => 2 })
    fetcher = FakeFetcher.new(
      page_body(jobs: [ job(id: 1) ], next_cursor: "c1"),
      page_body(jobs: [ job(id: 2) ], next_cursor: "c2"),
      page_body(jobs: [ job(id: 3) ], next_cursor: "c3")
    )

    candidates = adapter(fetcher).scan(source_scan:, window_days: 20)

    assert_equal 2, fetcher.urls.size
    assert_equal %w[1 2], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "stops on an empty page even when nextCursor is still present" do
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      page_body(jobs: [ job(id: 1) ], next_cursor: "c1"),
      page_body(jobs: [], next_cursor: "c2"),
      page_body(jobs: [ job(id: 3) ], next_cursor: nil)
    )

    candidates = adapter(fetcher).scan(source_scan:, window_days: 20)

    assert_equal 2, fetcher.urls.size
    assert_equal %w[1], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "keeps each job id once when the same vacancy repeats on the same or the next page" do
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      page_body(jobs: [ job(id: 7), job(id: 7) ], next_cursor: "c1"),
      page_body(jobs: [ job(id: 7), job(id: 8) ], next_cursor: nil)
    )

    candidates = adapter(fetcher).scan(source_scan:, window_days: 20)

    assert_equal %w[7 8], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "drops vacancies published before the scan window" do
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      page_body(jobs: [ job(id: 1, published_at: 2.days.ago), job(id: 2, published_at: 40.days.ago) ], next_cursor: nil)
    )

    candidates = adapter(fetcher).scan(source_scan:, window_days: 20)

    assert_equal %w[1], candidates.map { |candidate| candidate[:external_job_id] }
  end

  test "rejects USA-only and unstated eligibility, and accepts LATAM, Brazil and Anywhere" do
    source_scan = build_source_scan
    fetcher = FakeFetcher.new(
      page_body(
        jobs: [
          job(id: 1, geo: "USA"),
          job(id: 2, geo: "UK,  Canada,  USA"),
          job(id: 3, geo: "EMEA,  LATAM,  Canada,  USA"),
          job(id: 4, geo: "Brazil"),
          job(id: 5, geo: "Anywhere"),
          job(id: 6, geo: "")
        ],
        next_cursor: nil
      )
    )

    candidates = adapter(fetcher).scan(source_scan:, window_days: 20)

    assert_equal %w[3 4 5], candidates.map { |candidate| candidate[:external_job_id] }
    assert candidates.all? { |candidate| %w[strong borderline].include?(candidate[:classification]) }
  end

  test "points apply, canonical and source links at the original Jobicy listing" do
    source_scan = build_source_scan
    listing_url = "https://jobicy.com/jobs/159101-senior-ruby-on-rails-engineer"
    fetcher = FakeFetcher.new(
      page_body(jobs: [ job(id: 159_101, url: listing_url, company: "Welo Global", geo: "Brazil") ], next_cursor: nil)
    )

    candidate = adapter(fetcher).scan(source_scan:, window_days: 20).first

    assert_equal "Jobicy", candidate[:source_name]
    assert_equal "jobicy", candidate[:source_slug]
    assert_equal "Welo Global", candidate[:company_name]
    assert_equal "159101", candidate[:external_job_id]
    assert_equal listing_url, candidate[:apply_url]
    assert_equal listing_url, candidate[:canonical_url]
    assert_equal listing_url, candidate[:source_url]
  end

  private
    def adapter(fetcher)
      JobDiscovery::Adapters::JobicyJobsApiAdapter.new(fetcher:)
    end

    def build_source_scan(settings: {})
      source = job_sources(:workable)
      source.update!(adapter_key: "jobicy_jobs_api", supports_backfill: true, scan_window_days: 7, settings:)
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end

    def page_body(jobs:, next_cursor:)
      {
        "apiVersion" => "2.2.19",
        "jobCount" => jobs.size,
        "nextCursor" => next_cursor,
        "hasMore" => next_cursor.present?,
        "appliedFilters" => { "count" => 100, "geo" => "brazil" },
        "jobs" => jobs,
        "statusCode" => 200,
        "success" => true
      }.to_json
    end

    def job(id:, url: "https://jobicy.com/jobs/#{id}-senior-ruby-on-rails-engineer", geo: "Brazil", published_at: 2.days.ago, company: "Acme Remote")
      {
        "id" => id,
        "url" => url,
        "jobSlug" => "#{id}-senior-ruby-on-rails-engineer",
        "jobTitle" => "Senior Ruby on Rails Engineer",
        "companyName" => company,
        "jobIndustry" => [ "Software Engineering" ],
        "jobType" => [ "Full-Time" ],
        "jobGeo" => geo,
        "jobLevel" => "Senior",
        "jobExcerpt" => "Remote Rails role.",
        "jobDescription" => "<p>Build Ruby on Rails services.</p>",
        "pubDate" => published_at.iso8601
      }
    end
end
