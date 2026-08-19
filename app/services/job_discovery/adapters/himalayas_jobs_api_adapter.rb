require "json"

module JobDiscovery
  module Adapters
    # Public JSON feed from Himalayas (https://himalayas.app/jobs/api).
    # Remote-focused board; the API returns the company slug as the reliable
    # company identifier (companyName is a placeholder in the feed).
    class HimalayasJobsApiAdapter < Base
      API_URL = "https://himalayas.app/jobs/api".freeze
      PLACEHOLDER_COMPANY_NAME = "name".freeze

      def scan(source_scan:, window_days:)
        page_limit = [ source_scan.job_source.settings.fetch("max_pages", 3).to_i, 1 ].max
        results_per_page = [ source_scan.job_source.settings.fetch("results_per_page", 50).to_i, 1 ].max
        cutoff = window_days.days.ago.beginning_of_day
        candidates = []

        page_limit.times do |page|
          source_scan.record_page!
          payload = JSON.parse(fetcher.call("#{API_URL}?#{URI.encode_www_form(limit: results_per_page, offset: page * results_per_page)}"))
          jobs = Array(payload["jobs"])
          break if jobs.empty?

          jobs.each do |job|
            candidate = build_candidate_from_job(source_scan:, job:, cutoff:)
            candidates << candidate if candidate
          end
        end

        candidates
      end

      private
        def build_candidate_from_job(source_scan:, job:, cutoff:)
          title = job["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = epoch_time(job["pubDate"])
          return if published_at.present? && published_at < cutoff
          return if expired?(job["expiryDate"])

          url = job["applicationLink"].presence || job["guid"].to_s
          return if url.blank?

          restrictions = Array(job["locationRestrictions"]).compact_blank

          build_candidate(
            source_scan:,
            source_name: "Himalayas",
            source_kind: "platform",
            source_slug: "himalayas",
            title:,
            company_name: company_name(job),
            apply_url: url.delete_suffix("/"),
            canonical_url: job["guid"].to_s.delete_suffix("/"),
            source_url: job["guid"].to_s.delete_suffix("/"),
            remote_text: [ "Remote", restrictions.join(", ") ].compact_blank.join(" | "),
            location_text: restrictions.join(", "),
            description: job["description"].presence || job["excerpt"].to_s,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["guid"].to_s,
            payload: {
              company_slug: job["companySlug"],
              employment_type: job["employmentType"],
              seniority: job["seniority"],
              min_salary: job["minSalary"],
              max_salary: job["maxSalary"],
              currency: job["currency"],
              salary_period: job["salaryPeriod"],
              categories: job["categories"],
              parent_categories: job["parentCategories"],
              timezone_restrictions: job["timezoneRestrictions"]
            }
          )
        end

        def company_name(job)
          raw = job["companyName"].to_s
          return job["companySlug"].to_s.titleize if raw.blank? || raw == PLACEHOLDER_COMPANY_NAME

          raw
        end

        def expired?(value)
          expiry = epoch_time(value)
          expiry.present? && expiry < Time.current
        end

        def epoch_time(value)
          Time.zone.at(Integer(value)) if value.present?
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
