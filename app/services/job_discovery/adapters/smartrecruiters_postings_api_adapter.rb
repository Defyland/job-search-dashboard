require "json"

module JobDiscovery
  module Adapters
    class SmartrecruitersPostingsApiAdapter < Base
      API_URL = "https://api.smartrecruiters.com/v1/companies".freeze
      HOST_SUFFIX = "smartrecruiters.com".freeze
      PAGE_SIZE = 100

      def scan(source_scan:, window_days:)
        company_identifiers(source_scan).flat_map do |company_identifier|
          scan_company(source_scan:, company_identifier:, window_days:)
        end
      end

      private
        def scan_company(source_scan:, company_identifier:, window_days:)
          page_limit = [ source_scan.job_source.settings.fetch("max_pages", default_page_limit(window_days)).to_i, 1 ].max
          offset = 0
          pages_scanned = 0
          candidates = []
          cutoff = window_days.days.ago.beginning_of_day

          while pages_scanned < page_limit
            source_scan.record_page!
            pages_scanned += 1

            response = fetch_postings(company_identifier:, offset:)
            postings = Array(response["content"])
            break if postings.empty?

            postings.each do |posting|
              candidate = build_candidate_from_posting(source_scan:, company_identifier:, posting:, cutoff:)
              candidates << candidate if candidate
            end

            break if stale_page?(postings, cutoff)

            offset += PAGE_SIZE
          end

          candidates
        end

        def fetch_postings(company_identifier:, offset:)
          url = "#{API_URL}/#{company_identifier}/postings?#{URI.encode_www_form(limit: PAGE_SIZE, offset: offset)}"
          JSON.parse(fetcher.call(url))
        end

        def build_candidate_from_posting(source_scan:, company_identifier:, posting:, cutoff:)
          title = posting["name"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(posting["releasedDate"])
          return if published_at.present? && published_at < cutoff

          detail = fetch_detail(company_identifier:, posting_id: posting["id"])
          return unless detail["active"] == true

          apply_url = normalize_public_url(detail["applyUrl"])
          return if apply_url.blank?

          description = description_from_detail(detail)
          location = detail["location"].to_h

          build_candidate(
            source_scan:,
            source_name: "SmartRecruiters",
            source_kind: "ats",
            source_slug: "smartrecruiters",
            title: detail["name"].presence || title,
            company_name: detail.dig("company", "name").presence || company_name_for_url(apply_url) || company_identifier.to_s.tr("-", " ").titleize,
            apply_url:,
            canonical_url: apply_url,
            source_url: apply_url,
            remote_text: remote_signal(location),
            location_text: location["fullLocation"].presence || [ location["city"], location["region"], location["country"] ].compact_blank.join(", "),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: detail["uuid"].presence || detail["id"].to_s,
            payload: {
              company_identifier:,
              posting_id: detail["id"],
              job_id: detail["jobId"],
              job_ad_id: detail["jobAdId"],
              experience_level: detail.dig("experienceLevel", "label"),
              department: detail.dig("department", "label"),
              remote: location["remote"],
              hybrid: location["hybrid"]
            }
          )
        end

        def fetch_detail(company_identifier:, posting_id:)
          url = "#{API_URL}/#{company_identifier}/postings/#{posting_id}"
          JSON.parse(fetcher.call(url))
        end

        def description_from_detail(detail)
          sections = detail.dig("jobAd", "sections").to_h
          sections.values.map { |section| section["text"] }.compact_blank.join(" ")
        end

        def company_identifiers(source_scan)
          configured = Array(source_scan.job_source.settings["company_identifiers"])
          discovered = known_hosted_urls(host_suffixes: [ HOST_SUFFIX ]).filter_map do |url|
            extract_company_identifier(url)
          end

          (configured + discovered).map { |identifier| identifier.to_s.strip }.reject(&:blank?).uniq
        end

        def extract_company_identifier(url)
          uri = URI.parse(url)
          segments = uri.path.split("/").reject(&:blank?)

          case normalized_host(url)
          when "jobs.smartrecruiters.com"
            segments.first
          else
            if segments.first == "oneclick-ui" && segments.second == "company"
              segments.third
            end
          end
        rescue URI::InvalidURIError
          nil
        end

        def stale_page?(postings, cutoff)
          released_dates = postings.filter_map { |posting| parse_time(posting["releasedDate"]) }
          return false if released_dates.empty?

          released_dates.all? { |published_at| published_at < cutoff }
        end

        def remote_signal(location)
          return "Remote" if location["remote"] == true
          return "Híbrido" if location["hybrid"] == true

          location["fullLocation"].to_s
        end

        def normalize_public_url(url)
          uri = URI.parse(url.to_s)
          uri.query = nil
          uri.fragment = nil
          uri.to_s.delete_suffix("/")
        rescue URI::InvalidURIError
          url.to_s.strip.delete_suffix("/")
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def default_page_limit(window_days)
          window_days >= 20 ? 3 : 1
        end
    end
  end
end
