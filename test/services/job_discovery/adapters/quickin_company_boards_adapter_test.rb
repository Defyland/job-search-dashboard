require "test_helper"

class JobDiscovery::Adapters::QuickinCompanyBoardsAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch(url)
    end
  end

  test "discovers company slugs from persisted quickin jobs, paginates boards, and extracts active candidates" do
    source = JobSource.create!(
      name: "Quickin Test",
      slug: "quickin-test",
      host: "jobs.quickin.io",
      base_url: "https://jobs.quickin.io",
      source_kind: :ats,
      adapter_key: "quickin_company_boards",
      supports_backfill: true,
      scan_window_days: 20,
      settings: { "max_pages" => 3 }
    )
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Seed Quickin Job",
      company_name: "EVT",
      apply_url: "https://jobs.quickin.io/evtit/apply?job_id=69e8fbacad20d00013fb2f1a",
      canonical_url: "https://jobs.quickin.io/evtit/jobs/69e8fbacad20d00013fb2f1a",
      source_url: "https://jobs.quickin.io/evtit/jobs/69e8fbacad20d00013fb2f1a",
      fingerprint: "seed::quickin::evtit",
      remote_text: "Hybrid",
      location_text: "Indaiatuba, SP, BR"
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    page_one = <<~HTML
      <html>
        <body>
          <table>
            <tbody>
              <tr>
                <th><a href="https://jobs.quickin.io/evtit/jobs/69e8fbacad20d00013fb2f1a">Senior Frontend Engineer (React)</a></th>
                <td><span>Indaiatuba</span><span class="badge badge-secondary">Remote</span></td>
              </tr>
              <tr>
                <th><a href="https://jobs.quickin.io/evtit/jobs/junior-role">Analista Júnior</a></th>
                <td><span>São Paulo</span><span class="badge badge-secondary">On-site</span></td>
              </tr>
            </tbody>
          </table>
        </body>
      </html>
    HTML
    page_two = <<~HTML
      <html>
        <body>
          <table>
            <tbody>
              <tr>
                <th><a href="https://jobs.quickin.io/evtit/jobs/6a0000000000000000000001">Senior Ruby on Rails Engineer</a></th>
                <td><span>São Paulo</span><span class="badge badge-secondary">Remote</span></td>
              </tr>
            </tbody>
          </table>
        </body>
      </html>
    HTML
    empty_page = <<~HTML
      <html><body><table><tbody></tbody></table></body></html>
    HTML
    active_posted_at = 2.days.ago.iso8601
    active_valid_through = 8.days.from_now.iso8601
    expired_posted_at = 3.days.ago.iso8601
    expired_valid_through = 1.day.ago.iso8601

    active_detail = <<~HTML
      <html>
        <head>
          <script type="application/ld+json">
            {
              "@context": "http://schema.org/",
              "@type": "JobPosting",
              "title": "Senior Frontend Engineer (React)",
              "description": "<p>React remoto para produto B2B.</p>",
              "datePosted": "#{active_posted_at}",
              "validThrough": "#{active_valid_through}",
              "employmentType": "PJ",
              "hiringOrganization": { "@type": "Organization", "name": "EVT" },
              "jobLocation": {
                "@type": "Place",
                "address": {
                  "@type": "PostalAddress",
                  "addressLocality": "Indaiatuba",
                  "addressRegion": "São Paulo",
                  "addressCountry": "BR"
                }
              },
              "identifier": { "@type": "PropertyValue", "value": "69e8fbacad20d00013fb2f1a" }
            }
          </script>
        </head>
        <body>
          <section>
            <h5><span>PJ,</span> <span>Indaiatuba</span> <span class="badge badge-secondary">Remote</span></h5>
          </section>
          <a href="/evtit/apply?job_id=69e8fbacad20d00013fb2f1a">Apply</a>
        </body>
      </html>
    HTML
    expired_detail = <<~HTML
      <html>
        <head>
          <script type="application/ld+json">
            {
              "@context": "http://schema.org/",
              "@type": "JobPosting",
              "title": "Senior Ruby on Rails Engineer",
              "description": "<p>Ruby on Rails remoto para LATAM.</p>",
              "datePosted": "#{expired_posted_at}",
              "validThrough": "#{expired_valid_through}",
              "employmentType": "CLT",
              "hiringOrganization": { "@type": "Organization", "name": "EVT" },
              "identifier": { "@type": "PropertyValue", "value": "6a0000000000000000000001" }
            }
          </script>
        </head>
        <body>
          <section>
            <h5><span>CLT,</span> <span>São Paulo</span> <span class="badge badge-secondary">Remote</span></h5>
          </section>
          <p>Vaga encerrada.</p>
        </body>
      </html>
    HTML

    adapter = JobDiscovery::Adapters::QuickinCompanyBoardsAdapter.new(
      fetcher: FakeFetcher.new(
        "https://jobs.quickin.io/evtit/jobs" => page_one,
        "https://jobs.quickin.io/evtit/jobs?page=2" => page_two,
        "https://jobs.quickin.io/evtit/jobs?page=3" => empty_page,
        "https://jobs.quickin.io/evtit/jobs/69e8fbacad20d00013fb2f1a" => active_detail,
        "https://jobs.quickin.io/evtit/jobs/6a0000000000000000000001" => expired_detail
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 2, candidates.size

    active_candidate = candidates.find { |candidate| candidate[:external_job_id] == "69e8fbacad20d00013fb2f1a" }
    assert_equal "strong", active_candidate[:classification]
    assert_equal "EVT", active_candidate[:company_name]
    assert_equal "https://jobs.quickin.io/evtit/apply?job_id=69e8fbacad20d00013fb2f1a", active_candidate[:apply_url]
    assert_equal "PJ", active_candidate[:payload][:employment_type]
    assert_equal "Remote", active_candidate[:remote_text]

    expired_candidate = candidates.find { |candidate| candidate[:external_job_id] == "6a0000000000000000000001" }
    assert_equal "expired", expired_candidate[:classification]
    assert_match(/encerrada|janela/, expired_candidate[:reason])
  end
end
