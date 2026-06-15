require "test_helper"

class JobDiscovery::Adapters::JobtargetHostedApplyAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "scans configured seed urls and extracts strong matches from hosted apply pages" do
    source = JobSource.create!(
      name: "JobTarget Test",
      slug: "jobtarget-test",
      host: "hosted-apply.jobtarget.com",
      base_url: "https://hosted-apply.jobtarget.com",
      source_kind: :ats,
      adapter_key: "jobtarget_hosted_apply",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        "seed_urls" => [
          "https://hosted-apply.jobtarget.com/job/Senior-Full-Stack-Engineer-Ruby-on-Rails-React-LATAM-Remote-XnkxWLcVeRG8qTJZGuKGdy?utm_source=linkedin"
        ]
      }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    detail_html = <<~HTML
      <html>
        <head>
          <title>Senior Full-Stack Engineer, Ruby on Rails / React - LATAM Remote in São Paulo, São Paulo - Brokerkit - Hosted Apply by JobTarget</title>
          <meta name="title" content="Senior Full-Stack Engineer, Ruby on Rails / React - LATAM Remote in São Paulo, São Paulo">
          <meta name="description" content="Brokerkit is hiring! We are looking for a motivated Senior Full-Stack Engineer, Ruby on Rails / React - LATAM Remote in São Paulo, São Paulo. Apply Now!">
          <meta property="og:title" content="Senior Full-Stack Engineer, Ruby on Rails / React - LATAM Remote in São Paulo, São Paulo">
          <meta property="og:url" content="https://hostedapply.jobtarget.com/job/Senior-Full-Stack-Engineer-Ruby-on-Rails-React-LATAM-Remote-XnkxWLcVeRG8qTJZGuKGdy">
        </head>
        <body>
          <h1>Senior Full-Stack Engineer, Ruby on Rails / React - LATAM Remote</h1>
          <span>
            <span class="item" title="Company">Brokerkit</span>
            <span class="item" title="Location">São Paulo, São Paulo, Brazil</span>
          </span>
          <div class="col_three_fifth nobottommargin">
            <div class="fancy-title title-double-border">
              <h4>About this position</h4>
            </div>
            <div class="row">
              <div class="col-md-12">
                <p>We are looking for a senior full-stack engineer who will work across Ruby on Rails backend/API and React frontend.</p>
                <p>This is a full-time remote contractor role for candidates based in Latin America.</p>
              </div>
            </div>
          </div>
          <button class="button button-rounded button-jt">Apply</button>
        </body>
      </html>
    HTML

    adapter = JobDiscovery::Adapters::JobtargetHostedApplyAdapter.new(
      fetcher: FakeFetcher.new(
        "https://hosted-apply.jobtarget.com/job/Senior-Full-Stack-Engineer-Ruby-on-Rails-React-LATAM-Remote-XnkxWLcVeRG8qTJZGuKGdy" => detail_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Brokerkit", candidates.first[:company_name]
    assert_equal "XnkxWLcVeRG8qTJZGuKGdy", candidates.first[:external_job_id]
    assert_equal "https://hostedapply.jobtarget.com/job/Senior-Full-Stack-Engineer-Ruby-on-Rails-React-LATAM-Remote-XnkxWLcVeRG8qTJZGuKGdy", candidates.first[:canonical_url]
    assert_equal "LATAM Remote", candidates.first[:remote_text]
  end

  test "marks known closed hosted apply pages as expired" do
    source = JobSource.create!(
      name: "JobTarget Closed Test",
      slug: "jobtarget-closed-test",
      host: "hosted-apply.jobtarget.com",
      base_url: "https://hosted-apply.jobtarget.com",
      source_kind: :ats,
      adapter_key: "jobtarget_hosted_apply",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {
        "seed_urls" => [
          "https://hosted-apply.jobtarget.com/jobs/Senior-Ruby-on-Rails-Engineer-66bf91a142feac428f1764bb"
        ]
      }
    )
    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    detail_html = <<~HTML
      <html>
        <head>
          <title>Senior Ruby on Rails Engineer in Arlington, Virginia - ExampleCo - Hosted Apply by JobTarget</title>
          <meta property="og:url" content="https://hosted-apply.jobtarget.com/jobs/Senior-Ruby-on-Rails-Engineer-66bf91a142feac428f1764bb">
        </head>
        <body>
          <h1>Senior Ruby on Rails Engineer</h1>
          <span>
            <span class="item" title="Company">ExampleCo</span>
            <span class="item" title="Location">Arlington, Virginia, United States</span>
          </span>
          <div class="col_three_fifth nobottommargin">
            <div class="row">
              <div class="col-md-12">
                <p>This job is no longer accepting applications.</p>
              </div>
            </div>
          </div>
        </body>
      </html>
    HTML

    adapter = JobDiscovery::Adapters::JobtargetHostedApplyAdapter.new(
      fetcher: FakeFetcher.new(
        "https://hosted-apply.jobtarget.com/jobs/Senior-Ruby-on-Rails-Engineer-66bf91a142feac428f1764bb" => detail_html
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "expired", candidates.first[:classification]
    assert_match "encerrada", candidates.first[:reason]
  end
end
