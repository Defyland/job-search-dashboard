module JobDiscovery
  module Adapters
    # GoGloby publishes a small, curated board of client roles on WordPress.
    # Discovery goes through the dedicated jobs sitemap, and each vacancy page
    # is server-rendered, so recency comes from the sitemap plus the page's own
    # `article:modified_time`. Applications are handled by an on-page form, so the
    # canonical vacancy URL is the applyable link.
    class GoglobyJobsSitemapAdapter < Base
      HOST = "gogloby.com".freeze
      SITEMAP_URL = "https://gogloby.com/jobs-sitemap.xml".freeze
      DEFAULT_MAX_JOBS = 25

      def scan(source_scan:, window_days:)
        max_jobs = [ source_scan.job_source.settings.fetch("max_jobs", DEFAULT_MAX_JOBS).to_i, 1 ].max

        job_references(source_scan).first(max_jobs).filter_map do |reference|
          source_scan.record_page!
          build_candidate_from_page(source_scan:, reference:, window_days:)
        end.uniq { |candidate| candidate.fetch(:canonical_url) }
      end

      private
        def job_references(source_scan)
          source_scan.record_page!
          sitemap = Nokogiri::XML(fetcher.call(sitemap_url(source_scan)))

          references = sitemap.css("url").filter_map do |node|
            url = normalized_job_url(node.at_css("loc")&.text)
            next unless url

            { url:, lastmod: parse_time(node.at_css("lastmod")&.text) }
          end

          references.uniq { |reference| reference.fetch(:url) }
                    .sort_by { |reference| -(reference[:lastmod]&.to_i || 0) }
        end

        def build_candidate_from_page(source_scan:, reference:, window_days:)
          document = html_document(reference.fetch(:url))
          title = extracted_title(document)
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(meta_content(document, "article:modified_time")) || reference[:lastmod]
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          canonical_url = normalized_job_url(canonical_link(document)) || reference.fetch(:url)
          position_type = extracted_position_type(document)
          description = extracted_description(document)

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "GoGloby",
            source_kind: source_scan.job_source.source_kind.presence || "platform",
            source_slug: source_scan.job_source.slug.presence || "gogloby",
            title:,
            company_name: source_scan.job_source.name.presence || "GoGloby",
            apply_url: canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text: remote_signal(position_type, description),
            location_text: location_signal(position_type),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: external_job_id_for(canonical_url),
            payload: {
              sitemap_lastmod: reference[:lastmod],
              position_type: position_type.presence,
              apply_flow: "gogloby_form"
            }
          )
        end

        def sitemap_url(source_scan)
          source_scan.job_source.settings["sitemap_url"].presence || SITEMAP_URL
        end

        def extracted_title(document)
          document.at_css("h2.block-title")&.text.to_s.squish.presence ||
            meta_content(document, "og:title").split("|").first.to_s.squish
        end

        # The vacancy header carries a single line such as
        # "Full-time / LATAM Based - Remote", which is the only structured
        # location and contract signal the page exposes.
        def extracted_position_type(document)
          # Only the page header describes this vacancy; `.position-type` nodes
          # belong to the "More jobs like this" carousel and would otherwise
          # leak another posting's location into this candidate.
          document.at_css(".block-header .block-description")&.text.to_s.squish.presence ||
            document.at_css(".block-description")&.text.to_s.squish
        end

        def extracted_description(document)
          document.css("h3.job-title").map do |heading|
            [ heading.text.to_s.squish, heading.next_element&.text.to_s.squish ].compact_blank.join(" ")
          end.compact_blank.join(" ").squish.presence || document.at_css("body")&.text.to_s.squish
        end

        def remote_signal(position_type, description)
          return position_type if position_type.to_s.match?(/remote|remoto/i)

          description.to_s[/(?:fullys+remote|remote[-s]?first|100%s+remote|remote|remoto)/i]&.squish
        end

        def location_signal(position_type)
          # The header reads "<contract> / <location>", and the location itself
          # can contain slashes ("4 days/week"), so only the first separator
          # splits contract from location.
          _contract, separator, location = position_type.to_s.partition("/")
          return position_type.to_s.squish if separator.blank?

          location.squish.presence || position_type.to_s.squish
        end

        def canonical_link(document)
          document.at_css("link[rel='canonical']")&.[]("href")
        end

        def meta_content(document, key)
          document.at_css("meta[property='#{key}']")&.[]("content").to_s.strip
        end

        def normalized_job_url(value)
          uri = URI.parse(value.to_s.strip)
          return unless normalized_host(uri.to_s) == HOST

          segments = uri.path.split("/").reject(&:blank?)
          return unless segments.length == 2 && segments.first == "jobs"

          "https://#{HOST}/jobs/#{segments.last}"
        rescue URI::InvalidURIError
          nil
        end

        def external_job_id_for(url)
          URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s.presence
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
