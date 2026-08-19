require "json"

module JobDiscovery
  module Adapters
    # Public beBee BR job search pages (https://bebee.com/br/jobs). Listings are
    # server-rendered into a Next.js RSC payload embedded in the HTML; this
    # adapter extracts the embedded jobs array and lets the profile policy decide.
    #
    # Note: beBee's robots.txt disallows /api/ and query-string search URLs, so
    # keep the request volume low (one page per configured query term, throttled
    # by the shared Fetcher) and honor the bot User-Agent.
    class BebeeJobsPageAdapter < Base
      SEARCH_URL = "https://bebee.com/br/jobs".freeze
      DEFAULT_SEARCH_QUERIES = %w[ruby react].freeze
      MAX_QUERIES = 6
      RSC_CHUNK_PATTERN = /self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)/m
      REMOTE_POLICY_LABELS = {
        "full_remote" => "100% Remoto",
        "hybrid" => "Híbrido",
        "on_site" => "Presencial"
      }.freeze

      def scan(source_scan:, window_days:)
        queries = configured_queries(source_scan)
        remote_filter = source_scan.job_source.settings.fetch("remote_filter", "full_remote")
        cutoff = window_days.days.ago.beginning_of_day
        candidates = []

        queries.each do |query|
          source_scan.record_page!
          html = fetcher.call(search_url(query, remote_filter))
          jobs = extract_jobs(html)
          next if jobs.empty?

          jobs.each do |job|
            candidate = build_candidate_from_job(source_scan:, job:, cutoff:)
            candidates << candidate if candidate
          end
        end

        candidates
      end

      private
        def configured_queries(source_scan)
          raw = source_scan.job_source.settings.fetch("search_queries", DEFAULT_SEARCH_QUERIES)
          Array(raw).filter_map { |value| value.to_s.strip.presence }.uniq.first(MAX_QUERIES)
        end

        def search_url(query, remote_filter)
          params = { q: query }
          params[:remote] = remote_filter if remote_filter.present?
          "#{SEARCH_URL}?#{URI.encode_www_form(params)}"
        end

        def extract_jobs(html)
          payload = html.scan(RSC_CHUNK_PATTERN).flatten.join
          return [] if payload.blank?

          unescaped = JSON.parse(%("#{payload}"))
          jobs_start = unescaped.index('"jobs":[')
          return [] unless jobs_start

          extract_array(unescaped, jobs_start + 7)
        rescue JSON::ParserError
          []
        end

        def extract_array(text, start_index)
          depth = 0
          in_string = false
          escaped = false
          index = start_index

          while index < text.length
            char = text[index]

            if in_string
              if escaped
                escaped = false
              elsif char == "\\"
                escaped = true
              elsif char == '"'
                in_string = false
              end
            else
              case char
              when '"'
                in_string = true
              when "["
                depth += 1
              when "]"
                depth -= 1
                return JSON.parse(text[start_index..index]) if depth.zero?
              end
            end

            index += 1
          end

          []
        rescue JSON::ParserError
          []
        end

        def build_candidate_from_job(source_scan:, job:, cutoff:)
          title = job["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job["started_date"])
          return if published_at.present? && published_at < cutoff

          url = job["url"].to_s
          return if url.blank?

          build_candidate(
            source_scan:,
            source_name: "beBee",
            source_kind: "aggregator",
            source_slug: "bebee",
            title:,
            company_name: job["publisher_name"].to_s.presence || "beBee",
            apply_url: url.delete_suffix("/"),
            canonical_url: url.delete_suffix("/"),
            source_url: url.delete_suffix("/"),
            remote_text: remote_policy_label(job["remote_policy"]),
            location_text: job["location_name"].to_s,
            description: job["description"].to_s,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              source_name: job["source_name"],
              robot_label: job["robot_label"],
              origin_type: job["origin_type"],
              feed_name: job["feed_name"],
              remote_policy: job["remote_policy"],
              contract_type: job["contract_type"],
              geoname_locality: job["geoname_locality"],
              bebee_direct: job["bebee_direct"],
              end_date: job["end_date"],
              primary_keywords: job["primary_keywords"]
            }
          )
        end

        def remote_policy_label(value)
          REMOTE_POLICY_LABELS.fetch(value.to_s, value.to_s.presence)
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
