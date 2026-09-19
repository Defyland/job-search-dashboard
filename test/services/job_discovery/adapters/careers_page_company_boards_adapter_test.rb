require "test_helper"

class JobDiscovery::Adapters::CareersPageCompanyBoardsAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def call(url, limit: 5, headers: {}, allowed_hosts: nil)
      @requests << url
      @responses.fetch(url)
    end
  end

  BOARD_URL = "https://customertimes.careers-page.com".freeze

  def build_source_scan(settings = {})
    source = JobSource.create!(
      name: "CustomerTimes Test",
      slug: "customertimes-test",
      host: "careers-page.com",
      base_url: BOARD_URL,
      source_kind: :ats,
      adapter_key: "careers_page_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings:
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
  end

  def board_page(postings)
    cards = postings.map do |url, title|
      <<~HTML
        <article class="job-card box-shadow-bg">
          <div class="jobs-content">
            <header class="jobs-header-row">
              <div class="jobs-title-wrapper">
                <a href="#{url}" class="job-title-link" data-job-id="abc" data-job-title="#{title}">
                  <h2 class="jobs-title text-brand-blue mb-0">#{title}</h2>
                </a>
              </div>
            </header>
          </div>
        </article>
      HTML
    end.join
    %(<html><body><main id="page-content">#{cards}</main></body></html>)
  end

  def job_page(title:, description: "Design and build Salesforce solutions using Apex and LWC.")
    <<~HTML
      <html><head>
        <title>#{title} | Customertimes</title>
        <meta property="og:title" content="#{title} | Customertimes" />
      </head><body>
      <main id="page-content">
        <div class="single-job-card rounded-border box-shadow-bg">
          <div class="single-job-content">
            <div class="single-job-header-row d-flex justify-content-start align-items-center mb-0">
              <h4 class="single-job-title">#{title}</h4>
            </div>
            <div class="job-location mt-4">
              <ul class="text-quarterary list-unstyled">
                <li class="d-flex gap-1">Full-Time</li>
                <li class="d-flex gap-1">Remote</li>
              </ul>
            </div>
            <div>
              <h5 class="job-title-h5 mt-4 mb-0">Job Description:</h5>
              <div class="text-heading-color mt-4 font-paragraph job-post-description">
                <p>#{description}</p>
              </div>
            </div>
          </div>
        </div>
      </main>
      </body></html>
    HTML
  end

  test "walks the board root and builds candidates from the server-rendered details" do
    rails_url = "#{BOARD_URL}/jobs/795fc99f-ff9b-4719-8999-fae6cc2743cb"
    ignored_url = "#{BOARD_URL}/jobs/2de83bf5-2951-4073-951d-4e12129fea90"
    source_scan = build_source_scan("board_urls" => [ BOARD_URL ])
    fetcher = FakeFetcher.new(
      BOARD_URL => board_page([
        [ rails_url, "Senior Ruby on Rails Engineer" ],
        [ ignored_url, "iOS Developer" ]
      ]),
      rails_url => job_page(title: "Senior Ruby on Rails Engineer"),
      ignored_url => job_page(title: "iOS Developer")
    )

    candidates = JobDiscovery::Adapters::CareersPageCompanyBoardsAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    candidate = candidates.first
    assert_equal "strong", candidate[:classification]
    assert_equal "Senior Ruby on Rails Engineer", candidate[:title]
    assert_equal "Customertimes", candidate[:company_name]
    assert_equal rails_url, candidate[:canonical_url]
    assert_equal "#{rails_url}/apply", candidate[:apply_url]
    assert_equal "Remote", candidate[:remote_text]
    assert_includes candidate[:location_text], "Full-Time"
    assert_includes candidate[:description], "Apex and LWC"
  end

  test "skips the apply route during board discovery and honours max_jobs" do
    url = "#{BOARD_URL}/jobs/795fc99f-ff9b-4719-8999-fae6cc2743cb"
    source_scan = build_source_scan("board_urls" => [ BOARD_URL ], "max_jobs" => 1)
    fetcher = FakeFetcher.new(
      BOARD_URL => board_page([
        [ url, "Senior Ruby on Rails Engineer" ],
        [ "#{BOARD_URL}/jobs/9189ea61-dd02-479e-a0f0-8c5dd2a91460", "Senior Ruby on Rails Developer" ]
      ]),
      url => job_page(title: "Senior Ruby on Rails Engineer")
    )

    candidates = JobDiscovery::Adapters::CareersPageCompanyBoardsAdapter.new(fetcher:).scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert fetcher.requests.none? { |requested| requested.end_with?("/apply") }
  end

  test "falls back to the board name when the page carries no company meta" do
    url = "#{BOARD_URL}/jobs/795fc99f-ff9b-4719-8999-fae6cc2743cb"
    source_scan = build_source_scan("board_urls" => [ BOARD_URL ])
    page = board_page([ [ url, "Senior Rails Engineer" ] ]).sub("| Customertimes", "")
    fetcher = FakeFetcher.new(
      BOARD_URL => page,
      url => job_page(title: "Senior Rails Engineer", description: "<p>Build Rails services.</p>")
    )

    candidate = JobDiscovery::Adapters::CareersPageCompanyBoardsAdapter.new(fetcher:).scan(source_scan:, window_days: 20).first

    assert_equal "Customertimes", candidate[:company_name]
    assert_equal "795fc99f-ff9b-4719-8999-fae6cc2743cb", candidate[:external_job_id]
  end
end
