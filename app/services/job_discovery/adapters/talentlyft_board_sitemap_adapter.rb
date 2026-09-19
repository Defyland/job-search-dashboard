module JobDiscovery
  module Adapters
    # TalentLift hosts each company's board at {company}.talentlyft.com. The
    # board sitemap carries every vacancy with a precise lastmod, and each
    # vacancy page server-renders a schema.org JobPosting block. robots.txt
    # disallows the list endpoints (/JobList, /joblist, ...) but explicitly
    # advertises the sitemap, so discovery goes through it and only in-window
    # postings cost a detail request.
    #
    # UNVERIFIED (2026-09-18): robots.txt declares "Crawl-delay: 150", which
    # the shared Fetcher does not honor (its default floor is 0.4s). The scan
    # is bounded by max_jobs and the window cutoff so the traffic is small, but
    # the terms of service were not reviewed. See README "Source provenance and
    # unverified terms".
    class TalentlyftBoardSitemapAdapter < Base
      HOST_SUFFIX = "talentlyft.com".freeze
      SITEMAP_PATH = "/sitemap.xml".freeze
      DEFAULT_MAX_JOBS = 12

      def scan(source_scan:, window_days:)
        settings = source_scan.job_source.settings
        max_jobs = bounded(settings["max_jobs"], DEFAULT_MAX_JOBS)
        cutoff = window_days.days.ago.beginning_of_day

        references = boards(source_scan).flat_map do |board_url|
          source_scan.record_page!
          job_references(source_scan:, board_url:, cutoff:, max_jobs:)
        end

        references.first(max_jobs).filter_map do |reference|
          source_scan.record_page!
          build_candidate_from_page(source_scan:, board_url: reference.fetch(:board_url), reference:, cutoff:)
        end.uniq { |candidate| candidate.fetch(:canonical_url) }
      end

      private
        def job_references(source_scan:, board_url:, cutoff:, max_jobs:)
          sitemap = Nokogiri::XML(fetcher.call(sitemap_url(source_scan, board_url), allowed_hosts: [ host_for(board_url) ]))

          sitemap.css("url").filter_map do |node|
            url = normalized_job_url(node.at_css("loc")&.text, board_url)
            next unless url

            lastmod = parse_time(node.at_css("lastmod")&.text)
            next if lastmod.present? && lastmod < cutoff

            { url:, lastmod:, board_url: }
          end.uniq { |reference| reference.fetch(:url) }
            .sort_by { |reference| -(reference[:lastmod]&.to_i || 0) }
            .first(max_jobs)
        end

        def build_candidate_from_page(source_scan:, board_url:, reference:, cutoff:)
          document = html_document(reference.fetch(:url), allowed_hosts: [ host_for(board_url) ])
          posting = parse_job_posting_json(document)
          title = posting["title"].to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(posting["datePosted"]) || reference[:lastmod]
          return if published_at.present? && published_at < cutoff

          canonical_url = normalized_job_url(posting["url"], board_url) || reference.fetch(:url)
          address = posting_location_address(posting)
          location_text = address.values_at("addressLocality", "addressRegion", "addressCountry", "streetAddress")
            .compact_blank.join(", ")
          description = description_text(posting)

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "TalentLift",
            source_kind: source_scan.job_source.source_kind.presence || "ats",
            source_slug: source_scan.job_source.slug.presence || "talentlyft",
            title:,
            company_name: posting.dig("hiringOrganization", "name").to_s.squish.presence || "Empresa nao identificada",
            apply_url: canonical_url,
            canonical_url:,
            source_url: reference.fetch(:url),
            remote_text: remote_signal(location_text, description),
            location_text:,
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: external_job_id_for(canonical_url),
            payload: {
              board_url:,
              sitemap_lastmod: reference[:lastmod],
              employment_type: posting["employmentType"],
              company_site: posting.dig("hiringOrganization", "sameAs")
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

        def host_for(board_url)
          URI.parse(board_url).host
        rescue URI::InvalidURIError
          nil
        end

        def sitemap_url(source_scan, board_url)
          source_scan.job_source.settings["sitemap_url"].presence || "#{board_url}#{SITEMAP_PATH}"
        end

        # The sitemap loc is the canonical posting; the "new application" route
        # (/{slug}/new) is the apply form for the same posting and must not be
        # treated as a separate vacancy.
        def normalized_job_url(value, board_url)
          uri = URI.parse(value.to_s.strip)
          return unless normalized_host(uri.to_s) == host_for(board_url)

          segments = uri.path.split("/").reject(&:blank?)
          segments.pop if segments.last == "new"
          return unless segments.length == 2 && segments.first == "jobs"

          "#{uri.scheme}://#{uri.host}/jobs/#{segments.last}"
        rescue URI::InvalidURIError
          nil
        end

        def posting_location_address(posting)
          location = posting["jobLocation"]
          location.is_a?(Hash) ? location["address"].to_h : {}
        end

        def description_text(posting)
          body = posting["description"].to_s
          body = Nokogiri::HTML(body).text if body.include?("<")
          body.squish
        end

        def remote_signal(location_text, description)
          return "Remote" if location_text.to_s.match?(/remote|remoto|latam/i)

          tokens = description.to_s.downcase.scan(/[a-z]+/)
          return "Remote" if (tokens & %w[remote remoto latam]).any?

          nil
        end

        def external_job_id_for(url)
          URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s.presence
        rescue URI::InvalidURIError
          nil
        end

        def bounded(value, fallback)
          configured = value.is_a?(Numeric) || value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
          [ configured || fallback, 1 ].max
        end
    end
  end
end
