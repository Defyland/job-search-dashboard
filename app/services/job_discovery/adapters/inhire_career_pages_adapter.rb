require "cgi"
require "json"

module JobDiscovery
  module Adapters
    class InhireCareerPagesAdapter < Base
      API_URL = "https://api.inhire.app".freeze
      HOST = "inhire.app".freeze

      def scan(source_scan:, window_days:)
        career_page_slugs(source_scan).flat_map do |career_page_slug|
          source_scan.record_page!
          scan_career_page(source_scan:, career_page_slug:, window_days:)
        end
      end

      private
        def scan_career_page(source_scan:, career_page_slug:, window_days:)
          tenant = resolve_tenant(career_page_slug)
          return [] if tenant.blank?

          public_page = JSON.parse(fetcher.call("#{API_URL}/job-posts/public/pages", headers: tenant_headers(tenant.fetch("tenant_id"))))
          jobs = Array(public_page["jobsPage"])

          jobs.filter_map do |job|
            build_candidate_from_job(source_scan:, tenant:, job:, window_days:)
          end
        rescue JSON::ParserError, RuntimeError
          []
        end

        def build_candidate_from_job(source_scan:, tenant:, job:, window_days:)
          return unless job["status"] == "published"

          title = job["displayName"].to_s.squish
          return unless policy.potential_match?(title)

          detail = JSON.parse(fetcher.call(detail_url(job["jobId"]), headers: tenant_headers(tenant.fetch("tenant_id"))))
          published_at = parse_time(detail["lastPublishedAt"]) || parse_time(detail["publishedAt"]) || parse_time(detail["updatedAt"]) || parse_time(detail["createdAt"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          canonical_url = public_job_url(tenant.fetch("primary_subdomain"), detail["careerPageId"], job["jobId"])
          description = normalized_description(detail["description"])

          build_candidate(
            source_scan:,
            source_name: "Inhire",
            source_kind: "ats",
            source_slug: "inhire",
            title: detail["displayName"].presence || title,
            company_name: detail["tenantName"].presence || tenant.fetch("tenant_name"),
            apply_url: canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text: detail["workplaceType"].to_s,
            location_text: detail["location"].to_s,
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["jobId"].to_s,
            payload: {
              tenant_id: tenant.fetch("tenant_id"),
              career_page_slug: career_page_slug_for_job(job, detail["careerPageId"]),
              career_page_id: detail["careerPageId"],
              active_job_boards: Array(detail["activeJobBoards"])
            }
          )
        rescue JSON::ParserError, RuntimeError
          nil
        end

        def career_page_slugs(source_scan)
          configured = Array(source_scan.job_source.settings["career_page_slugs"])
          discovered = known_hosted_urls(host_suffixes: [ HOST ]).filter_map do |url|
            extract_career_page_slug(url)
          end

          (configured + discovered).map { |slug| slug.to_s.strip }.reject(&:blank?).uniq
        end

        def extract_career_page_slug(url)
          uri = URI.parse(url)
          host = normalized_host(url)
          return path_based_career_page_slug(uri) if host == HOST
          return unless host.end_with?(".#{HOST}")

          host.delete_suffix(".#{HOST}")
        rescue URI::InvalidURIError
          nil
        end

        def path_based_career_page_slug(uri)
          segments = uri.path.split("/").reject(&:blank?)
          return if segments.empty? || segments.first == "vagas"

          segments.first
        end

        def resolve_tenant(career_page_slug)
          response = JSON.parse(fetcher.call("#{API_URL}/tenants/public/resolve/#{URI.encode_www_form_component(career_page_slug)}"))

          {
            "tenant_id" => response.dig("subdomain", "tenantId").presence || response.dig("tenant", "id").to_s,
            "tenant_name" => response.dig("tenant", "name").to_s,
            "primary_subdomain" => response.dig("subdomain", "primarySubdomain").presence || response.dig("subdomain", "current").to_s
          }
        rescue JSON::ParserError
          {}
        end

        def detail_url(job_id)
          "#{API_URL}/job-posts/public/pages/#{job_id}"
        end

        def tenant_headers(tenant_id)
          { "X-Tenant" => tenant_id.to_s }
        end

        def public_job_url(primary_subdomain, career_page_id, job_id)
          path_prefix = career_page_id.present? && career_page_id != "default" ? "#{career_page_id}/" : ""
          "https://#{primary_subdomain}.inhire.app/#{path_prefix}vagas/#{job_id}"
        end

        def career_page_slug_for_job(job, career_page_id)
          if career_page_id.present? && career_page_id != "default"
            career_page_id
          else
            Array(job["careerPageIds"]).first.presence || job["careerPageId"].presence || "default"
          end
        end

        def normalized_description(value)
          Nokogiri::HTML.fragment(CGI.unescapeHTML(value.to_s)).text.squish
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
