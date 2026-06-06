module JobDiscovery
  module Adapters
    class AshbyJobBoardAdapter < Base
      BASE_URL = "https://jobs.ashbyhq.com".freeze
      HOST = "jobs.ashbyhq.com".freeze

      def scan(source_scan:, window_days:)
        board_slugs(source_scan).flat_map do |board_slug|
          source_scan.record_page!
          scan_board(source_scan:, board_slug:, window_days:)
        end
      end

      private
        def scan_board(source_scan:, board_slug:, window_days:)
          document = html_document("#{BASE_URL}/#{board_slug}")
          app_data = parse_window_app_data(document)
          organization_name = app_data.dig("organization", "name").presence || board_slug.to_s.tr("-", " ").titleize

          Array(app_data.dig("jobBoard", "jobPostings")).filter_map do |job_posting|
            build_candidate_from_posting(source_scan:, board_slug:, organization_name:, job_posting:, window_days:)
          end
        end

        def build_candidate_from_posting(source_scan:, board_slug:, organization_name:, job_posting:, window_days:)
          title = job_posting["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job_posting["updatedAt"]) || parse_time(job_posting["publishedDate"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          job_url = "#{BASE_URL}/#{board_slug}/#{job_posting["id"]}"
          remote_text = job_posting["workplaceType"].to_s
          location_text = location_signal(job_posting)

          build_candidate(
            source_scan:,
            source_name: "Ashby",
            source_kind: "ats",
            source_slug: "ashby",
            title:,
            company_name: organization_name,
            apply_url: job_url,
            canonical_url: job_url,
            source_url: job_url,
            remote_text:,
            location_text:,
            description: "",
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job_posting["id"].to_s,
            payload: {
              board_slug:,
              team_name: job_posting["teamName"],
              department_name: job_posting["departmentName"],
              workplace_type: job_posting["workplaceType"],
              location_name: job_posting["locationName"],
              secondary_locations: Array(job_posting["secondaryLocations"]).map { |entry| entry["locationName"] }
            }
          )
        end

        def board_slugs(source_scan)
          configured = Array(source_scan.job_source.settings["board_slugs"])
          discovered = known_hosted_urls(host_suffixes: [ HOST ]).filter_map do |url|
            extract_board_slug(url)
          end

          (configured + discovered).map { |slug| slug.to_s.strip }.reject(&:blank?).uniq
        end

        def extract_board_slug(url)
          uri = URI.parse(url)
          return unless normalized_host(url) == HOST

          uri.path.split("/").reject(&:blank?).first
        rescue URI::InvalidURIError
          nil
        end

        def location_signal(job_posting)
          primary = job_posting["locationName"].to_s.squish
          secondary = Array(job_posting["secondaryLocations"]).map { |entry| entry["locationName"].to_s.squish }.reject(&:blank?)
          [ primary, secondary.join(", ") ].reject(&:blank?).join(" | ")
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
