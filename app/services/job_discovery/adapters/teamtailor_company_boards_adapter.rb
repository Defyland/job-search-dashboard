module JobDiscovery
  module Adapters
    class TeamtailorCompanyBoardsAdapter < Base
      HOST_SUFFIX = "teamtailor.com".freeze

      def scan(source_scan:, window_days:)
        board_urls(source_scan).flat_map do |board_url|
          scan_board(source_scan:, board_url:, window_days:)
        end
      end

      private
        def scan_board(source_scan:, board_url:, window_days:)
          page_limit = [ source_scan.job_source.settings.fetch("max_pages", default_page_limit(window_days)).to_i, 1 ].max
          candidates = []
          next_page_url = "#{board_url}/jobs"
          pages_scanned = 0

          while next_page_url.present? && pages_scanned < page_limit
            source_scan.record_page!
            pages_scanned += 1

            document = html_document(next_page_url)
            cards = extract_job_cards(document, next_page_url)
            break if cards.empty?

            cards.each do |card|
              candidate = build_candidate_from_card(source_scan:, board_url:, card:, window_days:)
              candidates << candidate if candidate
            end

            next_page_url = next_show_more_url(document, board_url)
          end

          candidates
        end

        def build_candidate_from_card(source_scan:, board_url:, card:, window_days:)
          return unless policy.potential_match?(card.fetch(:title))

          detail = job_detail(card.fetch(:url))
          return unless active_job_page?(detail.fetch(:document))

          published_at = parse_time(detail.fetch(:posting)["datePosted"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          title = detail.fetch(:posting)["title"].presence || card.fetch(:title)
          description = detail.fetch(:posting)["description"].to_s
          company_name = detail.fetch(:posting).dig("hiringOrganization", "name").presence ||
            company_name_for_url(card.fetch(:url)) ||
            board_name_from_url(board_url)

          build_candidate(
            source_scan:,
            source_name: "Teamtailor",
            source_kind: "ats",
            source_slug: "teamtailor",
            title:,
            company_name:,
            apply_url: card.fetch(:url),
            canonical_url: card.fetch(:url),
            source_url: card.fetch(:url),
            remote_text: card[:remote_text],
            location_text: card[:location_text],
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: card.fetch(:url)[%r{/jobs/(\d+)}, 1].to_s,
            payload: {
              board_url:,
              department: card[:department],
              metadata: card[:metadata],
              direct_apply: detail.fetch(:posting)["directApply"],
              employment_type: detail.fetch(:posting)["employmentType"]
            }
          )
        end

        def board_urls(source_scan)
          configured = Array(source_scan.job_source.settings["board_urls"])
          discovered = known_hosted_urls(host_suffixes: [ HOST_SUFFIX ]).filter_map do |url|
            extract_board_url(url)
          end

          (configured + discovered).map { |url| canonical_url_string(url) }.reject(&:blank?).uniq
        end

        def extract_board_url(url)
          uri = URI.parse(url)
          path_segments = uri.path.split("/").reject(&:blank?)
          return unless path_segments.first == "jobs"

          "#{uri.scheme}://#{uri.host}"
        rescue URI::InvalidURIError
          nil
        end

        def extract_job_cards(document, page_url)
          document.css("a[href]").filter_map do |anchor|
            href = anchor["href"].to_s
            next unless href.include?("/jobs/")
            next if href.include?("/jobs/show_more")

            title = anchor.text.to_s.squish
            next if title.blank?

            metadata = extract_card_metadata(anchor)

            {
              title:,
              url: canonical_url_string(absolute_url(page_url, href)),
              department: metadata[:department],
              remote_text: metadata[:remote_text],
              location_text: metadata[:location_text],
              metadata: metadata[:segments]
            }
          end.uniq { |card| card[:url] }
        end

        def extract_card_metadata(anchor)
          container = anchor.parent
          metadata_node = container.css("div").find { |node| node != anchor && node.text.to_s.squish.present? }
          segments = metadata_node&.css("span")&.map { |span| span.text.to_s.squish }&.reject { |segment| segment.blank? || segment == "·" } || []

          department = segments.first
          work_mode = segments.find { |segment| segment.match?(/\b(remote|remoto|hybrid|h[ií]brido|on-?site|presencial)\b/i) }
          location_segments = segments.drop(1)
          location_segments = location_segments.reject { |segment| segment == work_mode } if work_mode.present?

          {
            department:,
            remote_text: work_mode,
            location_text: location_segments.join(", ").presence,
            segments:
          }
        end

        def next_show_more_url(document, board_url)
          href = document.at_css("a[href*='/jobs/show_more']")&.[]("href")
          return if href.blank?

          absolute_url(board_url, href)
        end

        def job_detail(url)
          document = html_document(url)
          posting = parse_job_posting_json(document)

          { document:, posting: }
        end

        def active_job_page?(document)
          text = document.text.to_s.squish
          text.match?(/Apply for this job|Loading application form/i)
        end

        def board_name_from_url(url)
          URI.parse(url).host.to_s.split(".").first.to_s.tr("-", " ").titleize
        rescue URI::InvalidURIError
          "Teamtailor"
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def default_page_limit(window_days)
          window_days >= 20 ? 6 : 2
        end
    end
  end
end
