module JobDiscovery
  module Adapters
    class LeverCompanyBoardsAdapter < Base
      API_URL = "https://api.lever.co/v0/postings".freeze
      HOST = "jobs.lever.co".freeze

      def scan(source_scan:, window_days:)
        company_slugs(source_scan).flat_map do |company_slug|
          source_scan.record_page!
          scan_company(source_scan:, company_slug:, window_days:)
        end
      end

      private
        def scan_company(source_scan:, company_slug:, window_days:)
          jobs = JSON.parse(fetcher.call("#{API_URL}/#{company_slug}?mode=json"))

          Array(jobs).filter_map do |job|
            build_candidate_from_job(source_scan:, company_slug:, job:, window_days:)
          end
        end

        def build_candidate_from_job(source_scan:, company_slug:, job:, window_days:)
          title = job["text"].presence || job["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job["createdAt"]) || parse_time(job["updatedAt"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          hosted_url = canonical_url_string(job["hostedUrl"])
          apply_url = canonical_url_string(job["applyUrl"].presence || hosted_url)
          remote_text = [ job["workplaceType"], job.dig("categories", "commitment") ].compact_blank.join(" ")
          location_text = location_signal(job)
          description = [
            job["descriptionPlain"],
            job["descriptionBodyPlain"],
            job["openingPlain"],
            job["additionalPlain"]
          ].compact_blank.join(" ")
          posted_text = published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica"
          decision = policy.classify(
            title:,
            remote_text:,
            location_text:,
            description:,
            source_slug: "lever",
            posted_text:,
            published_at:
          )
          return unless decision.accepted?

          build_candidate(
            source_scan:,
            source_name: "Lever",
            source_kind: "ats",
            source_slug: "lever",
            title:,
            company_name: company_name_for_lever_job(company_slug, hosted_url, apply_url),
            apply_url:,
            canonical_url: hosted_url.presence || apply_url,
            source_url: hosted_url.presence || apply_url,
            remote_text:,
            location_text:,
            description:,
            posted_text:,
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              company_slug:,
              categories: job["categories"],
              workplace_type: job["workplaceType"],
              country: job["country"]
            },
            decision:
          )
        end

        def company_slugs(source_scan)
          configured = Array(source_scan.job_source.settings["company_slugs"])
          discovered = known_hosted_urls(host_suffixes: [ HOST ]).filter_map do |url|
            extract_company_slug(url)
          end

          (configured + discovered).map { |slug| slug.to_s.strip }.reject(&:blank?).uniq
        end

        def extract_company_slug(url)
          uri = URI.parse(url)
          return unless normalized_host(url) == HOST

          uri.path.split("/").reject(&:blank?).first
        rescue URI::InvalidURIError
          nil
        end

        def company_name_for_lever_job(company_slug, hosted_url, apply_url)
          company_name_for_url(hosted_url) ||
            company_name_for_url(apply_url) ||
            company_slug.to_s.tr("-", " ").titleize
        end

        def location_signal(job)
          categories = job["categories"].to_h
          [ categories["location"], Array(categories["allLocations"]).join(", ") ].compact_blank.find(&:present?).to_s
        end

        def parse_time(value)
          case value
          when Integer
            Time.zone.at(value / 1000.0)
          when Float
            Time.zone.at(value / 1000.0)
          else
            Time.zone.parse(value.to_s)
          end
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
