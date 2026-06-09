require "test_helper"

class JobDiscovery::Adapters::InhireCareerPagesAdapterTest < ActiveSupport::TestCase
  class FakeFetcher
    def initialize(responses)
      @responses = responses
    end

    def call(url, limit: 5, headers: {})
      @responses.fetch([ url, headers["X-Tenant"] ])
    end
  end

  test "discovers career page slugs from persisted inhire jobs and extracts strong matches" do
    source = JobSource.create!(
      name: "Inhire Test",
      slug: "inhire-test",
      host: "inhire.app",
      base_url: "https://inhire.app",
      source_kind: :ats,
      adapter_key: "inhire_career_pages",
      supports_backfill: true,
      scan_window_days: 20,
      settings: {}
    )
    Job.create!(
      job_source: job_sources(:gupy),
      title: "Seed Inhire Job",
      company_name: "Deal Group",
      apply_url: "https://deal.inhire.app/vagas/8d53f515-4906-4536-a540-35c0f1419f2a/senior-react-native-engineer",
      canonical_url: "https://deal.inhire.app/vagas/8d53f515-4906-4536-a540-35c0f1419f2a/senior-react-native-engineer",
      source_url: "https://deal.inhire.app/vagas/8d53f515-4906-4536-a540-35c0f1419f2a/senior-react-native-engineer",
      fingerprint: "seed::inhire::deal",
      remote_text: "Remote",
      location_text: "Brazil"
    )

    search_run = SearchRun.create!(trigger_source: :manual, status: :running, window_label: "20d", started_at: Time.current)
    source_scan = search_run.source_scans.create!(job_source: source, status: :running, started_at: Time.current)

    tenant_response = {
      tenant: {
        id: "deal",
        name: "Deal Group"
      },
      subdomain: {
        current: "deal",
        tenantId: "deal",
        isPrimary: true,
        primarySubdomain: "deal"
      }
    }.to_json
    public_page_response = {
      tenantName: "Deal Group",
      jobsPage: [
        {
          jobId: "8d53f515-4906-4536-a540-35c0f1419f2a",
          careerPageId: "default",
          careerPageIds: [ "default" ],
          displayName: "Senior React Native Engineer",
          status: "published",
          workplaceType: "Remote",
          location: "Brazil"
        },
        {
          jobId: "other",
          careerPageId: "default",
          displayName: "Analista de Processos Júnior",
          status: "published",
          workplaceType: "Hybrid",
          location: "São Paulo, SP, BR"
        }
      ]
    }.to_json
    detail_response = {
      tenantName: "Deal Group",
      displayName: "Senior React Native Engineer",
      careerPageId: "default",
      activeJobBoards: [ "linkedin", "jobBoardPool" ],
      publishedAt: "2026-06-05T10:00:00Z",
      updatedAt: "2026-06-05T10:00:00Z",
      lastPublishedAt: "2026-06-05T10:00:00Z",
      description: "<p>React Native para produto remoto no Brasil.</p>",
      employmentType: "contractor",
      workplaceType: "Remote",
      location: "Brazil"
    }.to_json

    adapter = JobDiscovery::Adapters::InhireCareerPagesAdapter.new(
      fetcher: FakeFetcher.new(
        [ "https://api.inhire.app/tenants/public/resolve/deal", nil ] => tenant_response,
        [ "https://api.inhire.app/job-posts/public/pages", "deal" ] => public_page_response,
        [ "https://api.inhire.app/job-posts/public/pages/8d53f515-4906-4536-a540-35c0f1419f2a", "deal" ] => detail_response
      )
    )

    candidates = adapter.scan(source_scan:, window_days: 20)

    assert_equal 1, candidates.size
    assert_equal "strong", candidates.first[:classification]
    assert_equal "Deal Group", candidates.first[:company_name]
    assert_equal "8d53f515-4906-4536-a540-35c0f1419f2a", candidates.first[:external_job_id]
    assert_equal "https://deal.inhire.app/vagas/8d53f515-4906-4536-a540-35c0f1419f2a", candidates.first[:canonical_url]
    assert_equal "contractor", candidates.first[:payload][:contract_metadata]["employmentType"]
  end
end
