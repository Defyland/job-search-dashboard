require "test_helper"

class JobDiscovery::Adapters::LufloxPositionsAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "discovers active Luflox positions from the public Firestore feed" do
    source_scan = build_source_scan
    response = {
      "documents" => [
        firestore_document(
          id: "kWCKNjWHsbkWljOEbjBw",
          status: "ACTIVE",
          role: "Senior Rails Engineer (AI Enablement)"
        ),
        firestore_document(
          id: "closed-position",
          status: "CLOSED",
          role: "Senior Ruby Engineer"
        )
      ]
    }.to_json
    api_url = "https://firestore.googleapis.com/v1/projects/luflox-management-prod/databases/(default)/documents/positions?pageSize=100"
    adapter = JobDiscovery::Adapters::LufloxPositionsAdapter.new(
      fetcher: FakeFetcher.new(api_url => response)
    )

    travel_to Time.zone.parse("2026-08-19 12:00:00") do
      candidates = adapter.scan(source_scan:, window_days: 20)

      assert_equal 1, candidates.size
      assert_equal "strong", candidates.first[:classification]
      assert_equal "Luflox client", candidates.first[:company_name]
      assert_equal "REMOTE", candidates.first[:remote_text]
      assert_equal "LATAM", candidates.first[:location_text]
      assert_equal "kWCKNjWHsbkWljOEbjBw", candidates.first[:external_job_id]
      assert_equal "https://www.luflox.com/career/details/kWCKNjWHsbkWljOEbjBw/apply?status=ACTIVE", candidates.first[:apply_url]
    end
  end

  private
    def firestore_document(id:, status:, role:)
      {
        "name" => "projects/luflox-management-prod/databases/(default)/documents/positions/#{id}",
        "createTime" => "2026-08-04T17:07:24.949343Z",
        "fields" => {
          "id" => { "stringValue" => id },
          "status" => { "stringValue" => status },
          "role" => { "stringValue" => role },
          "modality" => { "stringValue" => "REMOTE" },
          "type" => { "stringValue" => "FULL-TIME" },
          "seniority" => { "stringValue" => "SR" },
          "description" => { "stringValue" => "Build production Ruby on Rails features for a remote LATAM team." },
          "requirements" => {
            "arrayValue" => {
              "values" => [
                { "stringValue" => "5+ years of Ruby on Rails experience." },
                { "stringValue" => "LATAM resident." }
              ]
            }
          },
          "creation" => {
            "mapValue" => {
              "fields" => {
                "date" => { "timestampValue" => "2026-08-04T17:07:24.897Z" }
              }
            }
          }
        }
      }
    end

    def build_source_scan
      source = JobSource.create!(
        name: "Luflox Test",
        slug: "luflox-test",
        host: "luflox.com",
        base_url: "https://www.luflox.com/career",
        source_kind: :company,
        adapter_key: "luflox_positions",
        supports_backfill: true,
        scan_window_days: 20,
        settings: { "max_pages" => 1 }
      )
      search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
      search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)
    end
end
