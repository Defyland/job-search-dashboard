require "json"
require "set"

module JobDiscovery
  module Adapters
    # Workable's public board API. The unfiltered feed carries ~170k live jobs
    # across every industry, so walking it page by page (20 rows each) is close
    # to useless for a stack-specific profile: a 15-page crawl reads 300 rows and
    # matched zero Ruby/Rails titles when measured on 2026-09-04.
    #
    # The endpoint accepts a `query` parameter, which the same crawl budget turns
    # into a real result set (`query=ruby` reports 278 matching jobs and returns
    # 11 Ruby titles on the first page alone). Discovery therefore runs one
    # paginated search per configured term instead of scanning the global feed.
    class WorkableGlobalApiAdapter < Base
      API_URL = "https://jobs.workable.com/api/v1/jobs".freeze
      DEFAULT_SEARCH_QUERIES = %w[ruby rails golang elixir react].freeze
      MAX_QUERIES = 8

      def scan(source_scan:, window_days:)
        page_limit = [ source_scan.job_source.settings.fetch("max_pages", default_page_limit(window_days)).to_i, 1 ].max
        seen_ids = Set.new
        candidates = []

        configured_queries(source_scan).each do |query|
          candidates.concat(
            scan_query(source_scan:, window_days:, page_limit:, query:, seen_ids:)
          )
        end

        candidates
      end

      private
        # A nil query keeps the original unfiltered feed behaviour, which is what
        # an operator gets by configuring `search_queries: []`.
        def scan_query(source_scan:, window_days:, page_limit:, query:, seen_ids:)
          next_page_token = nil
          candidates = []

          page_limit.times do
            source_scan.record_page!
            response = fetch_page(next_page_token, query:)
            jobs = Array(response["jobs"])
            break if jobs.empty?

            jobs.each do |job|
              # The same vacancy surfaces under several terms ("ruby" and
              # "rails"), so it must only be built once.
              next unless seen_ids.add?(job["id"].to_s)

              candidate = build_candidate_from_job(source_scan:, job:, window_days:)
              candidates << candidate if candidate
            end

            next_page_token = response["nextPageToken"].presence
            break if next_page_token.blank?
          end

          candidates
        end

        def fetch_page(next_page_token, query: nil)
          params = {}
          params[:query] = query if query.present?
          params[:nextPageToken] = next_page_token if next_page_token.present?
          url = params.empty? ? API_URL : "#{API_URL}?#{URI.encode_www_form(params)}"

          JSON.parse(fetcher.call(url))
        end

        def configured_queries(source_scan)
          settings = source_scan.job_source.settings
          return DEFAULT_SEARCH_QUERIES unless settings.key?("search_queries")

          queries = Array(settings["search_queries"]).map { |value| value.to_s.squish }.reject(&:blank?)
          # An explicitly empty list is an operator asking for the raw global
          # feed; `nil` is the "no query parameter" marker.
          return [ nil ] if queries.blank?

          queries.uniq.first(MAX_QUERIES)
        end

        def build_candidate_from_job(source_scan:, job:, window_days:)
          return unless job["state"] == "published"

          title = job["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job["updated"]) || parse_time(job["created"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          remote_text = workplace_signal(job)
          location_text = location_signal(job)

          build_candidate(
            source_scan:,
            source_name: "Workable",
            source_kind: "ats",
            source_slug: "workable",
            title:,
            company_name: job.dig("company", "title").presence || "Workable",
            apply_url: job["url"].to_s.delete_suffix("/"),
            canonical_url: job["url"].to_s.delete_suffix("/"),
            source_url: job["url"].to_s.delete_suffix("/"),
            remote_text:,
            location_text:,
            description: job["description"].to_s,
            posted_text: published_at ? "atualizada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              company_url: job.dig("company", "url"),
              employment_type: job["employmentType"],
              workplace: job["workplace"],
              location: job["location"]
            }
          )
        end

        def workplace_signal(job)
          workplace = job["workplace"].to_s
          workplace == "remote" ? "Remote" : workplace.humanize
        end

        def location_signal(job)
          location = job["location"].to_h
          [ location["city"], location["subregion"], location["countryName"] ].compact_blank.join(", ")
        end

        def default_page_limit(window_days)
          window_days >= 20 ? 15 : 5
        end
    end
  end
end
