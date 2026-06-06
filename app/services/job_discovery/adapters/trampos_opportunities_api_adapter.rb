require "json"

module JobDiscovery
  module Adapters
    class TramposOpportunitiesApiAdapter < Base
      API_URL = "https://trampos.co/api/v2/opportunities".freeze

      def scan(source_scan:, window_days:)
        page_limit = [ source_scan.job_source.settings.fetch("max_pages", default_page_limit(window_days)).to_i, 1 ].max
        cutoff = window_days.days.ago.beginning_of_day
        page = 1
        total_pages = nil
        candidates = []

        while page <= page_limit && (total_pages.nil? || page <= total_pages)
          source_scan.record_page!
          response = fetch_page(page)
          total_pages = response.dig("pagination", "total_pages").to_i if response["pagination"].present?
          opportunities = Array(response["opportunities"])
          break if opportunities.empty?

          opportunities.each do |opportunity|
            candidate = build_candidate_from_opportunity(source_scan:, opportunity:, cutoff:)
            candidates << candidate if candidate
          end

          break if stale_page?(opportunities, cutoff)

          page += 1
        end

        candidates
      end

      private
        def fetch_page(page)
          JSON.parse(fetcher.call("#{API_URL}?page=#{page}"))
        end

        def fetch_detail(opportunity_id)
          JSON.parse(fetcher.call("#{API_URL}/#{opportunity_id}")).fetch("opportunity")
        end

        def build_candidate_from_opportunity(source_scan:, opportunity:, cutoff:)
          title = opportunity["name"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(opportunity["published_at"])
          return if published_at.present? && published_at < cutoff

          detail = fetch_detail(opportunity["id"])
          canonical_url = normalize_public_url(detail["url"].presence || fallback_detail_url(opportunity["id"]))
          return if canonical_url.blank?

          apply_url = normalize_public_url(detail["apply_url"].presence || canonical_url)
          return if apply_url.blank?

          build_candidate(
            source_scan:,
            source_name: "Trampos",
            source_kind: "platform",
            source_slug: "trampos",
            title: detail["name"].presence || title,
            company_name: detail.dig("company", "name").presence || opportunity.dig("company", "name").presence || "Trampos",
            apply_url:,
            canonical_url:,
            source_url: canonical_url,
            remote_text: remote_signal(detail),
            location_text: location_text(detail),
            description: description_text(detail),
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: detail["id"].to_s,
            payload: {
              apply_method: detail["apply_method"],
              category_slug: detail["category_slug"],
              type_slug: detail["type_slug"],
              regime: detail["regime"],
              quantity: detail["quantity"],
              salary: detail["salary"],
              home_office: detail["home_office"],
              hybrid: detail["hybrid"],
              company_slug: detail.dig("company", "slug")
            }
          )
        end

        def description_text(detail)
          [
            detail["description"],
            detail["prerequisite"],
            detail["desirable"],
            detail["other_info"],
            detail["comments"]
          ].compact_blank.join(" ")
        end

        def remote_signal(detail)
          return "Home office" if detail["home_office"] == true
          return "Híbrido" if detail["hybrid"] == true

          location_text(detail)
        end

        def location_text(detail)
          [ detail["city"], detail["state"] ].compact_blank.join(", ")
        end

        def stale_page?(opportunities, cutoff)
          published_dates = opportunities.filter_map { |opportunity| parse_time(opportunity["published_at"]) }
          return false if published_dates.empty?

          published_dates.all? { |published_at| published_at < cutoff }
        end

        def fallback_detail_url(opportunity_id)
          "https://trampos.co/oportunidades/#{opportunity_id}"
        end

        def normalize_public_url(url)
          uri = URI.parse(url.to_s)
          uri.scheme = "https" if uri.scheme == "http"
          uri.query = nil
          uri.fragment = nil
          uri.to_s.delete_suffix("/")
        rescue URI::InvalidURIError
          url.to_s.strip.delete_suffix("/").sub(/\Ahttp:/, "https:")
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def default_page_limit(window_days)
          window_days >= 20 ? 20 : 6
        end
    end
  end
end
