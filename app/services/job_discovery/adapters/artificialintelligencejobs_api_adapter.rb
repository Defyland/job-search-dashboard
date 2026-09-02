require "json"

module JobDiscovery
  module Adapters
    # Public JSON API from artificialintelligencejobs.co (documented at /developers).
    #
    # The board aggregates AI-adjacent roles and keeps the employer's real apply
    # URL, so candidates canonicalize to the original ATS posting whenever the
    # board exposes one.
    #
    # UNVERIFIED (2026-08-26): the site started answering 403 behind a Vercel
    # security checkpoint for the homepage, robots.txt and this API alike. Its
    # terms of service have never been reviewed for automated collection. A 403
    # propagates as a failed scan on purpose, so the source is visibly blocked
    # rather than silently empty. See README "Source provenance and unverified
    # terms" before relying on it again.
    class ArtificialintelligencejobsApiAdapter < Base
      API_URL = "https://artificialintelligencejobs.co/api/jobs".freeze
      API_HOST = "artificialintelligencejobs.co".freeze
      DEFAULT_PAGE_SIZE = 50
      DEFAULT_MAX_PAGES = 4
      DEFAULT_MAX_DETAIL_PAGES = 12
      MAX_DESCRIPTION_CHARS = 8_000

      def scan(source_scan:, window_days:)
        settings = source_scan.job_source.settings
        page_size = bounded(settings["page_size"], DEFAULT_PAGE_SIZE)
        max_pages = bounded(settings["max_pages"], DEFAULT_MAX_PAGES)
        cutoff = window_days.days.ago.beginning_of_day
        candidates = []
        # A configured 0 must be honoured as "never fetch details", so this
        # floor is 0 rather than the 1 that page counters need.
        detail_budget = bounded(settings["max_detail_pages"], DEFAULT_MAX_DETAIL_PAGES, floor: 0)
        seen_jobs = 0

        max_pages.times do |page|
          source_scan.record_page!
          # A malformed page must not abort a scan that already collected rows.
          payload = parsed_page(page_url(page_size:, offset: page * page_size, settings:))
          break if payload.nil?

          jobs = Array(payload["jobs"])
          break if jobs.empty?

          seen_jobs += jobs.size
          jobs.each do |job|
            candidate = build_candidate_from_job(source_scan:, job:, cutoff:, detail_budget:)
            next unless candidate

            detail_budget -= 1 if candidate.delete(:fetched_detail)
            candidates << candidate
          end

          # Stop on the short page, or once every advertised row has been seen.
          # `matched` counts rows the API offers, not rows the policy accepted,
          # so comparing it against `candidates` truncated the scan whenever the
          # field was missing or most rows were filtered out.
          break if jobs.size < page_size
          break if reported_total(payload)&.then { |total| seen_jobs >= total }
        end

        deduped = candidates.uniq { |candidate| candidate.fetch(:canonical_url) }
        record_scan_metrics(source_scan, rows_seen: seen_jobs, candidates: candidates.size, deduped: deduped.size, detail_budget_left: detail_budget)
        deduped
      end

      private
        def build_candidate_from_job(source_scan:, job:, cutoff:, detail_budget:)
          title = job["title"].to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(job["posted"])
          return if published_at.present? && published_at < cutoff

          board_url = canonical_url_string(job["url"])
          return if board_url.blank?

          # Prefer the employer's own posting so this board dedupes against the
          # same vacancy discovered directly through its ATS.
          apply_url = canonical_url_string(job["apply_url"]).presence || board_url
          canonical_url = apply_url
          location = job["location"].to_s.squish
          # The list API carries no technologies, so the policy cannot confirm a
          # stack from it. Only titles that already pass the pre-filter earn a
          # detail request, which keeps the extra traffic bounded.
          detail = detail_budget.positive? ? detail_description(board_url) : nil
          description = [ metadata_description(job, location), detail ]
            .compact_blank.join(" | ")
            .truncate(MAX_DESCRIPTION_CHARS, omission: "")

          candidate = build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "Artificial Intelligence Jobs",
            source_kind: source_scan.job_source.source_kind.presence || "aggregator",
            source_slug: source_scan.job_source.slug.presence || "artificial-intelligence-jobs",
            title:,
            company_name: job["company"].to_s.squish.presence || "Empresa nao identificada",
            apply_url:,
            canonical_url:,
            source_url: board_url,
            remote_text: remote_signal(job, location),
            location_text: location,
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: external_job_id_for(board_url),
            payload: {
              board_url:,
              category: job["category"],
              level: job["level"],
              region: job["region"],
              salary: job["salary"],
              remote: job["remote"]
            }
          )
          candidate.merge(fetched_detail: detail.present?)
        end

        def metadata_description(job, location)
          [ job["category"], job["level"], job["region"], job["salary"], location ].compact_blank.join(" | ")
        end

        def parsed_page(url)
          payload = JSON.parse(fetcher.call(url, allowed_hosts: [ API_HOST ]))
          payload.is_a?(Hash) ? payload : nil
        rescue JSON::ParserError => error
          Rails.logger.warn("[artificialintelligencejobs] unparseable page #{url}: #{error.message}")
          nil
        end

        # `candidates_seen` on the scan only counts rows that survived the
        # pre-filter, which makes an aggregator look silent when it is simply
        # returning roles outside the profile. Recording rows offered by the API
        # separately keeps "nothing matched" distinguishable from "nothing came".
        def record_scan_metrics(source_scan, rows_seen:, candidates:, deduped:, detail_budget_left:)
          source_scan.update!(
            metadata: source_scan.metadata.to_h.merge(
              "api_rows_seen" => rows_seen,
              "candidates_built" => candidates,
              "candidates_after_dedupe" => deduped,
              "detail_budget_remaining" => detail_budget_left
            )
          )
        end

        # The board URL comes from a third-party payload, so it is validated
        # against this board's own host before being fetched. Without that a
        # hostile `url` could point the worker at an internal address and land
        # the response inside the candidate description.
        def detail_description(board_url)
          return unless detail_fetchable?(board_url)

          # Pin the redirect chain too: an allowed URL that redirects elsewhere
          # would otherwise still reach an arbitrary host.
          document = html_document(board_url, allowed_hosts: [ API_HOST ])
          document.css("script, style, noscript").each(&:remove)
          document.at_css("body")&.text.to_s.squish.presence
        rescue JobDiscovery::Fetcher::RequestError, Nokogiri::SyntaxError => error
          # Detail enrichment is best-effort, but a failure must stay visible
          # instead of silently degrading the candidate's stack signal.
          Rails.logger.warn("[artificialintelligencejobs] detail fetch failed for #{board_url}: #{error.class}: #{error.message}")
          nil
        end

        def detail_fetchable?(url)
          uri = URI.parse(url.to_s)
          uri.scheme == "https" && normalized_host(url) == API_HOST
        rescue URI::InvalidURIError
          false
        end

        def page_url(page_size:, offset:, settings:)
          params = { limit: page_size, offset: }
          params[:remote] = "true" if settings.fetch("remote_only", true)
          query = settings["query"].to_s.strip
          params[:q] = query if query.present?

          "#{API_URL}?#{URI.encode_www_form(params)}"
        end

        def remote_signal(job, location)
          return [ "Remote", location ].compact_blank.join(" | ") if job["remote"]

          location.presence
        end

        def bounded(value, fallback, floor: 1)
          # `value.presence` drops a literal 0, so an explicit numeric check is
          # needed for callers that must be able to configure zero.
          configured = value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+\z/) ? value.to_i : nil
          [ configured || fallback, floor ].max
        end

        # The API reports how many rows match the query. Only a sane positive
        # integer is trusted as a stop signal; anything else means "keep paging".
        def reported_total(payload)
          total = payload["matched"] || payload["total_live"]
          return unless total.is_a?(Numeric) || total.to_s.match?(/\A\d+\z/)

          value = total.to_i
          value.positive? ? value : nil
        end

        def external_job_id_for(url)
          URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s.presence
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
