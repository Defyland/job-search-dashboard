require "test_helper"

class JobDiscovery::Adapters::LoxoJobBoardAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "discovers matching jobs from a configured Loxo board" do
    source_scan = build_source_scan
    board_html = <<~HTML
      <div class="jobs-listing-card">
        <a class="job-title" href="/job/NDI0NzQtcmFpbHM=">Senior Ruby on Rails Engineer</a>
        <div class="job-date">2 days ago</div>
        <div class="job-type">Full Time</div>
        <div class="job-location"><i>wifi</i>Remote</div>
      </div>
    HTML
    detail_html = <<~HTML
      <html>
        <head>
          <title>Senior Ruby on Rails Engineer | FitNext Co.</title>
          <meta property="og:title" content="Senior Ruby on Rails Engineer">
          <meta property="og:url" content="https://pod6.app.loxo.co/job/NDI0NzQtcmFpbHM=?t=123">
        </head>
        <body>
          <div class="job-apply-card-header"></div>
          <div class="cleanslate">
            <p><strong>Location:</strong> Remote (LATAM)</p>
            <p><strong>Employment Type:</strong> Full-Time</p>
            <p>Build a Ruby on Rails backend and React frontend.</p>
          </div>
          <a class="job-apply-link" href="/job/NDI0NzQtcmFpbHM=/form?source_type=app">Apply for this job</a>
          <script type="application/json" id="public-job-description-json">{"description":"&lt;p&gt;&lt;strong&gt;Location:&lt;/strong&gt; Remote (LATAM)&lt;/p&gt;&lt;p&gt;Build a Ruby on Rails backend and React frontend.&lt;/p&gt;"}</script>
        </body>
      </html>
    HTML
    adapter = JobDiscovery::Adapters::LoxoJobBoardAdapter.new(
      fetcher: FakeFetcher.new(
        "https://pod6.app.loxo.co/fitnext" => board_html,
        "https://pod6.app.loxo.co/job/NDI0NzQtcmFpbHM=" => detail_html
      )
    )

    travel_to Time.zone.parse("2026-08-19 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      assert_equal "strong", candidates.first[:classification]
      assert_equal "FitNext Co.", candidates.first[:company_name]
      assert_equal "Remote", candidates.first[:remote_text]
      assert_equal "Remote", candidates.first[:location_text]
      assert_equal "NDI0NzQtcmFpbHM=", candidates.first[:external_job_id]
      assert_equal "https://pod6.app.loxo.co/job/NDI0NzQtcmFpbHM=/form?source_type=app", candidates.first[:apply_url]
    end
  end

  private
    def build_source_scan
      source = JobSource.create!(
        name: "Loxo Test",
        slug: "loxo-test",
        host: "app.loxo.co",
        base_url: "https://pod6.app.loxo.co/fitnext",
        source_kind: :ats,
        adapter_key: "loxo_job_board",
        supports_backfill: true,
        scan_window_days: 20,
        settings: { "board_urls" => [ "https://pod6.app.loxo.co/fitnext" ] }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end
end
