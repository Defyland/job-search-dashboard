require "json"

module JobDiscovery
  module Adapters
    # HiringCafe (https://hiringcafe.com) is a Next.js aggregator whose search UI
    # is client-side and whose search API answers 401. Discovery therefore goes
    # through the sitemaps the site itself advertises in robots.txt, and each
    # vacancy page ships a complete schema.org JobPosting block.
    #
    # robots.txt allows /job/ and /jobs/ but disallows /viewjob/, /org/,
    # /company/, /b/ and any URL carrying ?searchState= or ?page=, so this
    # adapter only ever touches /job/ detail pages reached from a sitemap.
    #
    # UNVERIFIED (2026-08-27): the host answered 403 behind a Vercel security
    # checkpoint on 2026-08-26 and answers 200 today, so the block may return.
    # A failure propagates as a failed scan on purpose. The terms of service have
    # not been reviewed for automated collection; see README "Source provenance
    # and unverified terms".
    class HiringcafeJobsSitemapAdapter < Base
      HOST = "hiringcafe.com".freeze
      INDEX_URL = "https://hiringcafe.com/job-posting-sitemap.xml".freeze
      DEFAULT_MAX_CHUNKS = 2
      DEFAULT_MAX_JOBS = 25

      def scan(source_scan:, window_days:)
        settings = source_scan.job_source.settings
        max_jobs = bounded(settings["max_jobs"], DEFAULT_MAX_JOBS)
        cutoff = window_days.days.ago.beginning_of_day
        references = job_references(source_scan:, settings:, cutoff:)

        candidates = references.first(max_jobs).filter_map do |reference|
          source_scan.record_page!
          build_candidate_from_page(source_scan:, reference:, cutoff:)
        end.uniq { |candidate| candidate.fetch(:canonical_url) }

        record_scan_metrics(source_scan, urls_seen: references.size, candidates: candidates.size)
        candidates
      end

      private
        # The index points at dated chunks; the newest ones are read first and
        # only URLs whose slug survives the title pre-filter earn a page request.
        def job_references(source_scan:, settings:, cutoff:)
          chunk_urls = sitemap_chunk_urls(source_scan:, settings:)
          references = []

          chunk_urls.each do |chunk_url|
            source_scan.record_page!
            references.concat(references_in(chunk_url, cutoff:))
          end

          references.uniq { |reference| reference.fetch(:url) }
                    .sort_by { |reference| -(reference[:lastmod]&.to_i || 0) }
        end

        def sitemap_chunk_urls(source_scan:, settings:)
          max_chunks = bounded(settings["max_chunks"], DEFAULT_MAX_CHUNKS)
          source_scan.record_page!
          index = parsed_sitemap(settings["sitemap_url"].presence || INDEX_URL)
          urls = index.css("loc").map { |node| node.text.to_s.strip }.select { |url| allowed_sitemap_url?(url) }
          urls.last(max_chunks).reverse
        end

        def references_in(chunk_url, cutoff:)
          parsed_sitemap(chunk_url).css("url").filter_map do |node|
            url = normalized_job_url(node.at_css("loc")&.text)
            next unless url

            lastmod = parse_time(node.at_css("lastmod")&.text)
            # The sitemap has tens of thousands of rows, so anything already
            # outside the window is dropped before it can cost a request.
            next if lastmod.present? && lastmod < cutoff
            # The slug carries the role title, which is enough to skip the vast
            # majority of unrelated postings without fetching them.
            next unless policy.potential_match?(title_from_slug(url))

            { url:, lastmod: }
          end
        end

        def build_candidate_from_page(source_scan:, reference:, cutoff:)
          # Every hop is pinned to this host: the URL comes from a third-party
          # document and must not be able to redirect the worker elsewhere.
          document = html_document(reference.fetch(:url), allowed_hosts: [ HOST ])
          posting = parse_job_posting_json(document)
          title = posting["title"].to_s.squish.presence || meta_content(document, "og:title").split(" at ").first.to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(posting["datePosted"]) || reference[:lastmod]
          return if published_at.present? && published_at < cutoff
          return if expired?(posting)

          canonical_url = reference.fetch(:url)

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "HiringCafe",
            source_kind: source_scan.job_source.source_kind.presence || "aggregator",
            source_slug: source_scan.job_source.slug.presence || "hiringcafe",
            title:,
            company_name: posting.dig("hiringOrganization", "name").to_s.squish.presence || "Empresa nao identificada",
            apply_url: canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text: remote_signal(posting),
            location_text: location_signal(posting),
            description: description_text(posting),
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: posting.dig("identifier", "value").to_s.squish.presence || external_job_id_for(canonical_url),
            payload: {
              sitemap_lastmod: reference[:lastmod],
              employment_type: Array(posting["employmentType"]).join(", ").presence,
              direct_apply: posting["directApply"],
              valid_through: posting["validThrough"],
              salary: posting["baseSalary"]
            }
          )
        end

        def expired?(posting)
          valid_through = parse_time(posting["validThrough"])
          valid_through.present? && valid_through < Time.current
        end

        def remote_signal(posting)
          return "Remote" if posting["jobLocationType"].to_s.casecmp?("TELECOMMUTE")

          location_signal(posting)
        end

        def location_signal(posting)
          address = Array.wrap(posting["jobLocation"]).filter_map { |place| place.is_a?(Hash) ? place["address"] : nil }.first.to_h
          location = [ address["addressLocality"], address["addressRegion"], address["addressCountry"] ].compact_blank.join(", ")
          return location if location.present?

          Array.wrap(posting["applicantLocationRequirements"]).filter_map { |value| value.is_a?(Hash) ? value["name"] : nil }.join(", ").presence
        end

        def description_text(posting)
          html = posting["description"].to_s
          return "" if html.blank?

          Nokogiri::HTML(html).text.squish
        end

        def title_from_slug(url)
          slug = URI.parse(url).path.split("/").reject(&:blank?).last.to_s
          # The trailing segment is an opaque id, and everything before it is the
          # role plus company and location, hyphen separated.
          slug.split("-")[0..-2].join(" ").squish
        rescue URI::InvalidURIError
          ""
        end

        def allowed_sitemap_url?(url)
          normalized_host(url) == HOST && URI.parse(url.to_s).path.include?("job-posting-sitemap")
        rescue URI::InvalidURIError
          false
        end

        def normalized_job_url(value)
          uri = URI.parse(value.to_s.strip)
          return unless normalized_host(uri.to_s) == HOST

          segments = uri.path.split("/").reject(&:blank?)
          # robots.txt only allows /job/ and /jobs/; anything else is skipped.
          return unless segments.length == 2 && segments.first == "job"

          "https://#{HOST}/job/#{segments.last}"
        rescue URI::InvalidURIError
          nil
        end

        def parsed_sitemap(url)
          Nokogiri::XML(fetcher.call(url, allowed_hosts: [ HOST ]))
        end

        def record_scan_metrics(source_scan, urls_seen:, candidates:)
          source_scan.update!(
            metadata: source_scan.metadata.to_h.merge(
              "sitemap_urls_seen" => urls_seen,
              "candidates_built" => candidates
            )
          )
        end

        def meta_content(document, key)
          document.at_css("meta[property='#{key}']")&.[]("content").to_s.strip
        end

        def external_job_id_for(url)
          URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s.split("-").last.presence
        rescue URI::InvalidURIError
          nil
        end

        def bounded(value, fallback)
          configured = value.is_a?(Numeric) || value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
          [ configured || fallback, 1 ].max
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
