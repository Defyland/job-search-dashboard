module JobDiscovery
  module Adapters
    class GupyCompanyBoardsAdapter < Base
      def scan(source_scan:, window_days:)
        board_urls(source_scan).flat_map do |board_url|
          source_scan.record_page!
          scan_board(source_scan:, board_url:, window_days:)
        end
      end

      private
        def scan_board(source_scan:, board_url:, window_days:)
          document = html_document(board_url)
          company_name = document.at_css("title")&.text.to_s.squish

          document.css("a[href*='/jobs/']").filter_map do |anchor|
            raw_title = anchor.text.to_s.squish
            next unless policy.potential_match?(raw_title)

            job_url = absolute_url(board_url, anchor["href"])
            detail = html_document(job_url)
            posting = parse_job_posting_json(detail)
            title = posting["title"].presence || raw_title
            description = posting["description"].to_s
            apply_url = extract_apply_url(detail, job_url)
            remote_text = [ anchor.text.to_s, posting["jobLocationType"] ].join(" ")
            published_at = parse_time(posting["datePosted"])
            next if published_at.present? && published_at < window_days.days.ago.beginning_of_day

            external_job_id = job_url[%r{/jobs/(\d+)}, 1]

            build_candidate(
              source_scan:,
              source_name: "Gupy",
              source_kind: "ats",
              source_slug: "gupy",
              title:,
              company_name: posting.dig("hiringOrganization", "name").presence || company_name,
              apply_url:,
              canonical_url: job_url,
              source_url: job_url,
              remote_text:,
              location_text: nil,
              description:,
              posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
              published_at:,
              external_job_id:,
              payload: {
                board_url:,
                raw_title:,
                json_ld: posting
              }
            )
          end
        end

        def board_urls(source_scan)
          configured_urls = Array(source_scan.job_source.settings["board_urls"])
          discovered_urls = Job.where(job_source: source_scan.job_source).pluck(:canonical_url, :source_url, :apply_url).flatten.compact.filter_map do |url|
            next if url.blank?

            host = URI.parse(url).host
            "https://#{host}/" if host.present? && host.end_with?("gupy.io")
          rescue URI::InvalidURIError
            nil
          end

          (configured_urls + discovered_urls).map { |url| url.to_s.strip }.reject(&:blank?).uniq
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
