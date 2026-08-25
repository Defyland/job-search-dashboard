require "test_helper"

class JobDiscovery::Adapters::NotionPublicPagesAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def post(url, body:, headers: {})
      payload = JSON.parse(body).fetch("pageId")
      @requests << [ url, payload ]
      @responses.fetch(payload)
    end
  end

  test "reads a public Notion page through loadPageChunk and normalizes the id" do
    source_scan = build_source_scan(page_urls: [
      "https://gogloby.notion.site/Senior-Full-Stack-Ruby-on-Rails-Developer-3ad2af3d743680ac8f29ec22df48b623"
    ])
    page_id = "3ad2af3d-7436-80ac-8f29-ec22df48b623"
    fetcher = FakeFetcher.new(
      page_id => chunk_payload(
        page_id:,
        title: "Senior Full Stack Ruby on Rails Developer",
        created_at: Time.zone.parse("2026-08-20 12:00:00"),
        blocks: [
          "This is a hands-on role. Full-time, LATAM based, fully remote.",
          "Strong production experience building full-stack web applications with Ruby on Rails."
        ]
      )
    )
    adapter = JobDiscovery::Adapters::NotionPublicPagesAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-25 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      candidate = candidates.first
      assert_equal "strong", candidate[:classification]
      assert_equal "Senior Full Stack Ruby on Rails Developer", candidate[:title]
      assert_equal "GoGloby", candidate[:company_name]
      assert_equal "fully remote", candidate[:remote_text]
      assert_equal "LATAM", candidate[:location_text]
      assert_equal page_id, candidate[:external_job_id]
      assert_equal "notion_page", candidate.dig(:payload, :apply_flow)
      assert_equal 1, source_scan.reload.pages_scanned

      # The dashless URL id must be requested as the dashed API id.
      assert_equal [ page_id ], fetcher.requests.map(&:last)
    end
  end

  test "skips pages outside the window and titles the policy rejects" do
    stale_id = "3ad2af3d-7436-80ac-8f29-ec22df48b111"
    junior_id = "3ad2af3d-7436-80ac-8f29-ec22df48b222"
    source_scan = build_source_scan(page_urls: [
      "https://gogloby.notion.site/Senior-Rails-Engineer-3ad2af3d743680ac8f29ec22df48b111",
      "https://gogloby.notion.site/Junior-Rails-Developer-3ad2af3d743680ac8f29ec22df48b222"
    ])
    fetcher = FakeFetcher.new(
      stale_id => chunk_payload(
        page_id: stale_id,
        title: "Senior Ruby on Rails Engineer",
        created_at: Time.zone.parse("2026-06-01 12:00:00"),
        blocks: [ "Remote role." ]
      ),
      junior_id => chunk_payload(
        page_id: junior_id,
        title: "Junior Ruby on Rails Developer",
        created_at: Time.zone.parse("2026-08-24 12:00:00"),
        blocks: [ "Remote role." ]
      )
    )
    adapter = JobDiscovery::Adapters::NotionPublicPagesAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-25 12:00:00") do
      assert_empty adapter.scan(source_scan:, window_days: 20)
    end
  end

  test "mirrored pages keep the origin site identity so both sources dedupe" do
    page_id = "3ad2af3d-7436-80ac-8f29-ec22df48b623"
    notion_url = "https://gogloby.notion.site/Senior-Full-Stack-Ruby-on-Rails-Developer-3ad2af3d743680ac8f29ec22df48b623"
    site_url = "https://gogloby.com/jobs/senior-full-stack-ruby-on-rails-developer"
    source_scan = build_source_scan(page_urls: [
      { "url" => notion_url, "mirror_of" => site_url }
    ])
    fetcher = FakeFetcher.new(
      page_id => chunk_payload(
        page_id:,
        title: "Senior Full Stack Ruby on Rails Developer",
        created_at: Time.zone.parse("2026-08-20 12:00:00"),
        blocks: [ "Full-time, LATAM based, fully remote Ruby on Rails role." ]
      )
    )
    adapter = JobDiscovery::Adapters::NotionPublicPagesAdapter.new(fetcher:)

    travel_to Time.zone.parse("2026-08-25 12:00:00") do
      candidate = adapter.scan(source_scan:, window_days: 20).first

      assert_equal site_url, candidate[:canonical_url]
      assert_equal notion_url, candidate[:apply_url]
      assert_equal notion_url, candidate[:source_url]
      assert_equal site_url, candidate.dig(:payload, :mirror_of)
      assert_includes candidate[:fingerprint], "gogloby.com"
      assert_not_includes candidate[:fingerprint], "notion.site"
      assert_equal "senior-full-stack-ruby-on-rails-developer", candidate[:external_job_id]
      assert_equal page_id, candidate.dig(:payload, :notion_page_id)
    end
  end

  private
    def build_source_scan(page_urls:)
      source = JobSource.create!(
        name: "GoGloby Notion Test",
        slug: "gogloby-notion-test",
        host: "gogloby.notion.site",
        base_url: "https://gogloby.notion.site",
        source_kind: :company,
        adapter_key: "notion_public_pages",
        supports_backfill: true,
        scan_window_days: 20,
        settings: { "company_name" => "GoGloby", "page_urls" => page_urls }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end

    # Mirrors Notion's nested `value.value` block shape.
    def chunk_payload(page_id:, title:, created_at:, blocks:)
      children = blocks.each_with_index.to_h do |text, index|
        [ "#{page_id}-child-#{index}", { "value" => { "value" => { "id" => "#{page_id}-child-#{index}", "type" => "text", "properties" => { "title" => [ [ text ] ] } } } } ]
      end

      {
        "recordMap" => {
          "block" => {
            page_id => {
              "value" => {
                "value" => {
                  "id" => page_id,
                  "type" => "page",
                  "properties" => { "title" => [ [ title ] ] },
                  "created_time" => created_at.to_i * 1000,
                  "last_edited_time" => created_at.to_i * 1000
                }
              }
            }
          }.merge(children)
        }
      }.to_json
    end
end
