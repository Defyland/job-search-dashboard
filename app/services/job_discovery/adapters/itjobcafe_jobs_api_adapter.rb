require "json"
require "set"

module JobDiscovery
  module Adapters
    # ITJobCafe (https://www.itjobcafe.com) renders its listings client-side with
    # AngularJS, so the HTML pages carry no vacancies and the sitemap exposes no
    # job URLs. The controller at /js/NgScripts/JobSearch/jobs.js calls a public
    # JSON endpoint with no authentication, which is what this adapter consumes.
    #
    # The listing payload already carries the same description the detail page
    # renders, so no per-job request is made: one POST per configured query is
    # enough and there is no third-party URL to follow.
    #
    # UNVERIFIED (2026-08-27): robots.txt only disallows SemrushBot, AhrefsBot
    # and Baidu, and this endpoint is not under a disallowed path, but the site
    # terms of service have never been reviewed for automated collection. See
    # README "Source provenance and unverified terms".
    class ItjobcafeJobsApiAdapter < Base
      API_URL = "https://www.itjobcafe.com/JobSearch/GetLatestJobs".freeze
      DETAIL_URL = "https://www.itjobcafe.com/Jobprocess/jobdetail".freeze
      APPLY_URL = "https://www.itjobcafe.com/JobProcess/GetMyJob1".freeze
      DEFAULT_SEARCH_QUERIES = %w[ruby rails golang elixir react].freeze
      MAX_QUERIES = 8
      MAX_DESCRIPTION_CHARS = 8_000

      def scan(source_scan:, window_days:)
        cutoff = window_days.days.ago.beginning_of_day
        seen_ids = Set.new
        rows_seen = 0
        candidates = []

        configured_queries(source_scan).each do |query|
          source_scan.record_page!
          jobs = fetch_jobs(query:, location: configured_location(source_scan))
          rows_seen += jobs.size

          jobs.each do |job|
            external_id = job["ID"].to_s.squish
            # The endpoint returns overlapping result sets across queries, so a
            # row already built must not be counted or emitted twice.
            next if external_id.blank? || !seen_ids.add?(external_id)

            candidate = build_candidate_from_job(source_scan:, job:, external_id:, cutoff:)
            candidates << candidate if candidate
          end
        end

        record_scan_metrics(source_scan, rows_seen:, candidates: candidates.size)
        candidates
      end

      private
        def fetch_jobs(query:, location:)
          body = { keywords: query, location: }.to_json
          payload = JSON.parse(fetcher.post(API_URL, body:))
          payload.is_a?(Array) ? payload : []
        rescue JSON::ParserError => error
          # A malformed answer for one query must not abort the remaining ones,
          # but it stays visible in the logs instead of looking like "no jobs".
          Rails.logger.warn("[itjobcafe] unparseable payload for #{query.inspect}: #{error.message}")
          []
        end

        def build_candidate_from_job(source_scan:, job:, external_id:, cutoff:)
          title = job["Title"].to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_relative_time(job["PostedOn"]) || parse_time(job["PublishedDate"]) || parse_time(job["PostedDate"])
          return if published_at.present? && published_at < cutoff

          location_text = [ job["City"], job["State"] ].map { |value| value.to_s.squish }.compact_blank.join(", ")
          description = job["BriefInfo"].to_s.squish.truncate(MAX_DESCRIPTION_CHARS, omission: "")

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "ITJobCafe",
            source_kind: source_scan.job_source.source_kind.presence || "aggregator",
            source_slug: source_scan.job_source.slug.presence || "itjobcafe",
            title:,
            company_name: job["Company"].to_s.squish.presence || "Empresa nao identificada",
            apply_url: "#{APPLY_URL}/#{external_id}",
            canonical_url: detail_url(external_id),
            source_url: detail_url(external_id),
            remote_text: remote_signal(title, location_text),
            location_text:,
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : job["PostedOn"].to_s.squish.presence || "sem data publica",
            published_at:,
            external_job_id: external_id,
            payload: {
              itjobcafe_id: external_id,
              posted_on: job["PostedOn"],
              city: job["City"],
              state: job["State"]
            }
          )
        end

        # The listing has no remote flag: the board mixes on-site and remote rows
        # and only signals it in the title. Passing the title through keeps the
        # profile policy in charge instead of asserting a remote role here.
        def remote_signal(title, location_text)
          return "Remote" if title.match?(/\bremote\b|telecommute/i)

          location_text.presence
        end

        def detail_url(external_id)
          "#{DETAIL_URL}?id=#{external_id}"
        end

        # "candidates_seen" only counts rows that survived the pre-filter, so the
        # rows actually offered by the endpoint are recorded separately to keep
        # "nothing matched" distinguishable from "nothing came back".
        def record_scan_metrics(source_scan, rows_seen:, candidates:)
          source_scan.update!(
            metadata: source_scan.metadata.to_h.merge(
              "api_rows_seen" => rows_seen,
              "candidates_built" => candidates
            )
          )
        end

        def configured_queries(source_scan)
          queries = Array(source_scan.job_source.settings["search_queries"]).map { |value| value.to_s.squish }.reject(&:blank?)
          (queries.presence || DEFAULT_SEARCH_QUERIES).uniq.first(MAX_QUERIES)
        end

        def configured_location(source_scan)
          source_scan.job_source.settings["location"].to_s.squish
        end

        # The endpoint only publishes a relative age ("7 Hours ago", "13 Days
        # ago"), so the window cutoff is derived from it.
        def parse_relative_time(value)
          match = value.to_s.downcase.match(/(\d+)\s+(hour|day|week|month|year)s?\s+ago/)
          return unless match

          amount = match[1].to_i
          duration = case match[2]
          when "hour" then amount.hours
          when "day" then amount.days
          when "week" then amount.weeks
          when "month" then (amount * 30).days
          when "year" then amount.years
          end
          Time.current - duration
        end

        def parse_time(value)
          return if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
