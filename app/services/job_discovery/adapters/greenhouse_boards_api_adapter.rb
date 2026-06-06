require "cgi"

module JobDiscovery
  module Adapters
    class GreenhouseBoardsApiAdapter < Base
      API_URL = "https://boards-api.greenhouse.io/v1/boards".freeze
      HOSTS = %w[boards.greenhouse.io job-boards.greenhouse.io].freeze

      def scan(source_scan:, window_days:)
        board_tokens(source_scan).flat_map do |board_token|
          source_scan.record_page!
          scan_board(source_scan:, board_token:, window_days:)
        end
      end

      private
        def scan_board(source_scan:, board_token:, window_days:)
          response = JSON.parse(fetcher.call("#{API_URL}/#{board_token}/jobs?content=true"))

          Array(response["jobs"]).filter_map do |job|
            build_candidate_from_job(source_scan:, board_token:, job:, window_days:)
          end
        end

        def build_candidate_from_job(source_scan:, board_token:, job:, window_days:)
          title = job["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job["updated_at"]) || parse_time(job["first_published"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          absolute_url = canonical_url_string(job["absolute_url"])
          description = CGI.unescapeHTML(job["content"].to_s)
          location_text = job.dig("location", "name").to_s

          build_candidate(
            source_scan:,
            source_name: "Greenhouse",
            source_kind: "ats",
            source_slug: "greenhouse",
            title:,
            company_name: job["company_name"].presence || company_name_for_url(absolute_url) || board_token.to_s.tr("-", " ").titleize,
            apply_url: absolute_url,
            canonical_url: absolute_url,
            source_url: absolute_url,
            remote_text: location_text,
            location_text:,
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              board_token:,
              departments: Array(job["departments"]).map { |entry| entry["name"] },
              offices: Array(job["offices"]).map { |entry| entry["name"] }
            }
          )
        end

        def board_tokens(source_scan)
          configured = Array(source_scan.job_source.settings["board_tokens"])
          discovered = known_hosted_urls(host_suffixes: HOSTS).filter_map do |url|
            extract_board_token(url)
          end

          (configured + discovered).map { |token| token.to_s.strip }.reject(&:blank?).uniq
        end

        def extract_board_token(url)
          uri = URI.parse(url)
          return unless HOSTS.include?(normalized_host(url))

          uri.path.split("/").reject(&:blank?).first
        rescue URI::InvalidURIError
          nil
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
