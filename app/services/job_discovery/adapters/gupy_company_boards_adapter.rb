module JobDiscovery
  module Adapters
    class GupyCompanyBoardsAdapter < Base
      MAX_DISCOVERED_BOARDS = 25
      # Gupy hosts that are not a company board: the job portal itself.
      NON_BOARD_LABELS = %w[portal].freeze

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
            canonical_url = canonical_listing_url(job_url)

            build_candidate(
              source_scan:,
              source_name: "Gupy",
              source_kind: "ats",
              source_slug: "gupy",
              title:,
              company_name: posting.dig("hiringOrganization", "name").presence || company_name,
              apply_url:,
              canonical_url:,
              source_url: canonical_url,
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

        # Query parameters such as `jobBoardSource` tell where a listing was opened from, not which
        # listing it is, so the canonical url keeps only scheme, host and path.
        def canonical_listing_url(job_url)
          uri = URI.parse(job_url)
          uri.query = nil
          uri.fragment = nil
          uri.to_s
        end

        def board_urls(source_scan)
          configured_urls = Array(source_scan.job_source.settings["board_urls"]).map { |url| url.to_s.strip }.reject(&:blank?).uniq
          configured_hosts = configured_urls.map { |url| normalized_host(url) }

          discovered_hosts = known_hosted_urls(host_suffixes: [ "gupy.io" ])
            .filter_map { |url| normalized_host(url).presence }
            .select { |host| company_board_host?(host) }
            .uniq
            .sort
            .reject { |host| configured_hosts.include?(host) }

          # Configured boards are always kept. Dynamic discovery is capped at MAX_DISCOVERED_BOARDS distinct
          # hosts, not urls, so one scan cannot fan out to every Gupy host in the database.
          configured_urls + rotated_hosts(source_scan, discovered_hosts).map { |host| "https://#{host}/" }
        end

        def company_board_host?(host)
          label = host.delete_suffix(".gupy.io")
          label.present? && label != host && NON_BOARD_LABELS.exclude?(label)
        end

        # Each scan of the source takes the next MAX_DISCOVERED_BOARDS hosts after the previous scan's,
        # wrapping around, so every discovered board is reached over the scans and none is starved.
        def rotated_hosts(source_scan, hosts)
          return hosts if hosts.size <= MAX_DISCOVERED_BOARDS

          start = (previous_scan_count(source_scan) * MAX_DISCOVERED_BOARDS) % hosts.size
          hosts.rotate(start).first(MAX_DISCOVERED_BOARDS)
        end

        def previous_scan_count(source_scan)
          source_scan.job_source.source_scans.where("source_scans.id < ?", source_scan.id).count
        end
    end
  end
end
