require "test_helper"

class JobDiscovery::Adapters::BaseTest < ActiveSupport::TestCase
  class ExposedAdapter < JobDiscovery::Adapters::Base
    def exposed_known_hosted_urls(host_suffixes:)
      known_hosted_urls(host_suffixes:)
    end

    def exposed_company_name_for_url(url)
      company_name_for_url(url)
    end
  end

  test "loads known URLs only for requested host suffixes" do
    greenhouse_url = "https://job-boards.greenhouse.io/example/jobs/123"
    unrelated_url = "https://jobs.lever.co/example/456"
    create_job!(
      company_name: "Greenhouse Co",
      canonical_url: greenhouse_url,
      fingerprint: "greenhouse::known"
    )
    create_job!(
      company_name: "Lever Co",
      canonical_url: unrelated_url,
      fingerprint: "lever::known"
    )

    urls = ExposedAdapter.new.exposed_known_hosted_urls(host_suffixes: [ "greenhouse.io" ])

    assert_equal [ greenhouse_url ], urls
  end

  test "finds company name by normalized known URL without loading every job" do
    canonical_url = "https://clicksign.gupy.io/jobs/11233965"
    create_job!(
      company_name: "Clicksign",
      canonical_url: "#{canonical_url}/",
      fingerprint: "gupy::clicksign"
    )

    assert_equal "Clicksign", ExposedAdapter.new.exposed_company_name_for_url(canonical_url)
  end

  private
    def create_job!(company_name:, canonical_url:, fingerprint:)
      Job.create!(
        job_source: job_sources(:gupy),
        title: "Senior Software Engineer",
        company_name:,
        apply_url: canonical_url,
        canonical_url:,
        source_url: canonical_url,
        fingerprint:,
        remote_text: "Remote",
        location_text: "Brazil"
      )
    end
end
