module JobDiscovery
  module Adapters
    # Careers-Page (careers-page.com) hosts each company's board at
    # {company}.careers-page.com. There is no sitemap, no robots.txt and no
    # JSON-LD, but the board root server-renders every vacancy card (title +
    # posting link) and each posting page server-renders the description and
    # location, so discovery walks the root page and fetches the details of
    # titles that pass the pre-filter.
    #
    # UNVERIFIED (2026-09-18): the boards answer 404 for /robots.txt and
    # /sitemap.xml, so there is no robots directive to consult and no Terms of
    # Service was reviewed. See README "Source provenance and unverified
    # terms".
    class CareersPageCompanyBoardsAdapter < Base
      HOST_SUFFIX = "careers-page.com".freeze
      DEFAULT_MAX_JOBS = 12

      def scan(source_scan:, window_days:)
        max_jobs = bounded(source_scan.job_source.settings["max_jobs"], DEFAULT_MAX_JOBS)

        boards(source_scan).flat_map do |board_url|
          source_scan.record_page!
          postings(board_url).first(max_jobs).filter_map do |posting|
            source_scan.record_page!
            build_candidate_from_page(source_scan:, board_url:, posting:, max_jobs:)
          end
        end.uniq { |candidate| candidate.fetch(:canonical_url) }
      end

      private
        def postings(board_url)
          document = html_document(board_url)
          document.css("a[href*='/jobs/']").filter_map do |anchor|
            href = anchor["href"].to_s
            next if href.end_with?("/apply")

            url = canonical_url_string(absolute_url(board_url, href))
            next unless url.match?(%r{/jobs/[0-9a-f-]+})

            title = anchor.at_css("h2")&.text.to_s.squish.presence || anchor["data-job-title"].to_s.squish
            { url:, title: }
          end.uniq { |posting| posting.fetch(:url) }
        end

        def build_candidate_from_page(source_scan:, board_url:, posting:, max_jobs:)
          title = posting.fetch(:title)
          return unless title.present? && policy.potential_match?(title)

          document = html_document(posting.fetch(:url))
          title = extracted_title(document).presence || title
          published_at = nil
          apply_url = "#{posting.fetch(:url)}/apply"
          location_text = extracted_location_text(document)
          description = extracted_description(document)

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "Careers-Page",
            source_kind: source_scan.job_source.source_kind.presence || "ats",
            source_slug: source_scan.job_source.slug.presence || "careers-page",
            title:,
            company_name: extracted_company_name(document).presence || company_name_for_url(posting.fetch(:url)) || board_name_from_url(board_url),
            apply_url:,
            canonical_url: posting.fetch(:url),
            source_url: posting.fetch(:url),
            remote_text: remote_signal(title, location_text, description),
            location_text:,
            description:,
            posted_text: "sem data publica",
            published_at:,
            external_job_id: external_job_id_for(posting.fetch(:url)),
            payload: {
              board_url:,
              job_id: anchor_job_id(posting.fetch(:url)),
              max_jobs:
            }
          )
        end

        def boards(source_scan)
          configured = Array(source_scan.job_source.settings["board_urls"])
          discovered = known_hosted_urls(host_suffixes: [ HOST_SUFFIX ]).filter_map do |url|
            board_url_for(url)
          end

          (configured + discovered).map { |url| canonical_url_string(url) }.reject(&:blank?).uniq
        end

        def board_url_for(url)
          uri = URI.parse(url.to_s)
          return unless normalized_host(uri.to_s).end_with?(HOST_SUFFIX)

          "#{uri.scheme || 'https'}://#{uri.host}"
        rescue URI::InvalidURIError
          nil
        end

        def extracted_title(document)
          document.at_css("h4.single-job-title")&.text.to_s.squish.presence ||
            meta_content(document, "og:title").split("|").first.to_s.squish.presence ||
            document.at_css("h2.jobs-title")&.text.to_s.squish
        end

        def extracted_company_name(document)
          meta_content(document, "og:title").to_s.split("|").last.to_s.squish.presence ||
            company_name_from_title(document)
        end

        def company_name_from_title(document)
          document.at_css("title")&.text.to_s[/|s*([^|]+)z/, 1]&.squish
        end

        def extracted_location_text(document)
          document.at_css(".job-location")&.css("li")&.map { |node| node.text.to_s.squish }
            &.compact_blank&.join(", ")
        end

        def extracted_description(document)
          document.at_css(".job-post-description")&.text.to_s.squish.presence ||
            document.at_css("#page-content")&.text.to_s.squish
        end

        def remote_signal(title, location_text, description)
          text = [ title, location_text, description ].compact_blank.join(" ")
          tokens = text.to_s.downcase.scan(/[a-z]+/)
          return "Remote" if (tokens & %w[remote remoto]).any?
          return "Remote" if location_text.to_s.downcase.scan(/[a-z]+/).include?("latam")

          nil
        end

        def meta_content(document, key)
          document.at_css("meta[property='#{key}']")&.[]("content").to_s.strip
        end

        def board_name_from_url(board_url)
          URI.parse(board_url).host.to_s.split(".").first.to_s.tr("-", " ").titleize
        rescue URI::InvalidURIError
          "Careers-Page"
        end

        def anchor_job_id(url)
          URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s.presence
        rescue URI::InvalidURIError
          nil
        end

        def external_job_id_for(url)
          anchor_job_id(url)
        end

        def bounded(value, fallback)
          configured = value.is_a?(Numeric) || value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
          [ configured || fallback, 1 ].max
        end
    end
  end
end
