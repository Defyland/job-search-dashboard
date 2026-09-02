module JobDiscovery
  module Adapters
    # HireRubyDevs (https://hirerubydevs.com) is a Ruby/Rails-only board. Its
    # `/jobs` listing is paginated (230+ pages), but the sitemap carries every
    # vacancy with a precise `lastmod`, so discovery sorts by recency there and
    # only fetches the pages worth reading.
    #
    # Each vacancy page server-renders a schema.org JobPosting block that already
    # includes a `skills` field ("rails, ruby"), which is fed to the policy as
    # part of the description so the stack signal does not depend on prose.
    #
    # robots.txt allows `/jobs` and disallows `/jobs/*/apply` and
    # `/jobs/*/website`, so the canonical vacancy page is both the identity and
    # the applyable link: the apply route is never requested.
    #
    # UNVERIFIED (2026-09-02): robots.txt carries a Cloudflare "Content-Signal"
    # header declaring `search=yes,ai-train=no,use=reference`. This adapter reads
    # the board to index and link back to postings, not to train a model, but the
    # site's terms of service were not reviewed. See README "Source provenance and
    # unverified terms".
    class HirerubydevsJobsSitemapAdapter < Base
      HOST = "hirerubydevs.com".freeze
      SITEMAP_URL = "https://hirerubydevs.com/sitemap.xml".freeze
      DEFAULT_MAX_JOBS = 30

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
        def job_references(source_scan:, settings:, cutoff:)
          source_scan.record_page!
          sitemap = parsed_sitemap(settings["sitemap_url"].presence || SITEMAP_URL)

          references = sitemap.css("url").filter_map do |node|
            url = normalized_job_url(node.at_css("loc")&.text)
            next unless url

            lastmod = parse_time(node.at_css("lastmod")&.text)
            # The sitemap lists every vacancy ever published, so rows already
            # outside the window are dropped before they can cost a request.
            next if lastmod.present? && lastmod < cutoff

            { url:, lastmod: }
          end

          references.uniq { |reference| reference.fetch(:url) }
                    .sort_by { |reference| -(reference[:lastmod]&.to_i || 0) }
        end

        def build_candidate_from_page(source_scan:, reference:, cutoff:)
          # URLs come from a third-party document, so every redirect hop is pinned
          # to this host.
          document = html_document(reference.fetch(:url), allowed_hosts: [ HOST ])
          posting = parse_job_posting_json(document)
          title = posting["title"].to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(posting["datePosted"]) || reference[:lastmod]
          return if published_at.present? && published_at < cutoff

          canonical_url = normalized_job_url(posting["url"]) || reference.fetch(:url)
          description = description_text(posting)

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "HireRubyDevs",
            source_kind: source_scan.job_source.source_kind.presence || "platform",
            source_slug: source_scan.job_source.slug.presence || "hirerubydevs",
            title:,
            company_name: posting.dig("hiringOrganization", "name").to_s.squish.presence || "Empresa nao identificada",
            # robots.txt disallows /jobs/*/apply, so the vacancy page stays the
            # applyable link and the apply route is never fetched.
            apply_url: canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text: remote_signal(posting, description),
            location_text: location_signal(posting),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: identifier_value(posting).presence || external_job_id_for(canonical_url),
            payload: {
              sitemap_lastmod: reference[:lastmod],
              skills: posting["skills"],
              valid_through: posting["validThrough"],
              direct_apply: posting["directApply"],
              company_site: posting.dig("hiringOrganization", "sameAs")
            },
            decision: expired_decision(posting, published_at)
          )
        end

        # Some rows carry a `validThrough` that predates their own `datePosted`
        # (observed on 2026-09-02: posted 09-02, valid through 08-16), which is a
        # stale field on a freshly republished vacancy rather than a real expiry.
        # Trusting it blindly would bury active postings, so a `validThrough`
        # older than the posting date is ignored.
        def expired_decision(posting, published_at)
          valid_through = parse_time(posting["validThrough"])
          return if valid_through.blank?
          return if published_at.present? && valid_through <= published_at
          return if valid_through >= Time.current

          expired_result
        end

        def expired_result
          reason = "vaga fora da validade no HireRubyDevs"
          JobDiscovery::Policy::Result.new(
            classification: :expired,
            reason:,
            stack_tags: [],
            score: 0,
            seniority: "senior",
            remote_signal: nil,
            exclusion_reason: reason,
            search_profile: nil,
            eligibility_flags: []
          )
        end

        # The board publishes a `skills` string ("rails, ruby") that the plain
        # description may never repeat, so it is prepended to keep the stack
        # signal available to the policy.
        def description_text(posting)
          body = posting["description"].to_s
          body = Nokogiri::HTML(body).text if body.include?("<")

          [ posting["skills"].to_s.squish.presence, body.squish.presence ].compact.join(" | ")
        end

        def remote_signal(posting, description)
          location = location_signal(posting)
          return "Remote" if location.to_s.match?(/remote|remoto/i)
          return "Remote" if posting["jobLocationType"].to_s.casecmp?("TELECOMMUTE")

          location.presence || description.to_s[/(?:fully\s+remote|100%\s+remote|remote)/i]
        end

        def location_signal(posting)
          address = Array.wrap(posting["jobLocation"]).filter_map { |place| place.is_a?(Hash) ? place["address"] : nil }.first.to_h
          [ address["addressLocality"], address["addressRegion"], address["addressCountry"] ].compact_blank.join(", ")
        end

        def identifier_value(posting)
          identifier = posting["identifier"]
          identifier.is_a?(Hash) ? identifier["value"].to_s.squish : identifier.to_s.squish
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

        def normalized_job_url(value)
          uri = URI.parse(value.to_s.strip)
          return unless normalized_host(uri.to_s) == HOST

          segments = uri.path.split("/").reject(&:blank?)
          # robots.txt disallows /jobs/*/apply and /jobs/*/website, so only the
          # two-segment vacancy path is accepted.
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
