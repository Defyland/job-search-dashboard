require "json"
require "set"

module JobDiscovery
  module Adapters
    # Public JSON feed from Jobicy (https://jobicy.com/api/jobs).
    #
    # The feed only returns vacancies published in the last 7 days. Pagination
    # is cursor based: `nextCursor` is opaque and must be sent back unchanged
    # with the same filters, so the filters stay fixed for the whole traversal.
    #
    # Attribution: Jobicy's terms require the source to be credited and every
    # apply action to go to the original listing, so apply, canonical and
    # source links all point at the Jobicy listing URL.
    class JobicyJobsApiAdapter < Base
      API_URL = "https://jobicy.com/api/jobs".freeze
      DEFAULT_GEO = "brazil".freeze
      DEFAULT_COUNT = 100
      MAX_COUNT = 100
      DEFAULT_MAX_PAGES = 3

      def scan(source_scan:, window_days:)
        settings = source_scan.job_source.settings
        page_limit = [ settings.fetch("max_pages", DEFAULT_MAX_PAGES).to_i, 1 ].max
        cutoff = window_days.days.ago.beginning_of_day
        seen_ids = Set.new
        candidates = []
        cursor = nil

        page_limit.times do
          source_scan.record_page!
          payload = JSON.parse(fetcher.call(page_url(settings, cursor)))
          jobs = Array(payload["jobs"])

          jobs.each do |job|
            # A vacancy can reappear on a later page, so it is only built once.
            next unless seen_ids.add?(job["id"].to_s)

            candidate = build_candidate_from_job(source_scan:, job:, cutoff:)
            candidates << candidate if candidate
          end

          cursor = payload["nextCursor"].presence
          break if cursor.nil? || jobs.empty?
        end

        candidates
      end

      private
        def page_url(settings, cursor)
          query = {
            geo: settings.fetch("geo", DEFAULT_GEO).to_s.squish.presence || DEFAULT_GEO,
            count: settings.fetch("count", DEFAULT_COUNT).to_i.clamp(1, MAX_COUNT),
            cursor:
          }.compact

          "#{API_URL}?#{URI.encode_www_form(query)}"
        end

        def build_candidate_from_job(source_scan:, job:, cutoff:)
          title = job["jobTitle"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job["pubDate"])
          return if published_at.present? && published_at < cutoff

          listing_url = job["url"].to_s.squish.delete_suffix("/")
          return if listing_url.blank?

          geo = job["jobGeo"].to_s.squish
          # Silently dropped, like the other adapters' out-of-scope vacancies.
          return unless eligible_geo?(geo)

          build_candidate(
            source_scan:,
            source_name: "Jobicy",
            source_kind: "platform",
            source_slug: "jobicy",
            title:,
            company_name: job["companyName"].to_s.squish.presence || "Jobicy",
            apply_url: listing_url,
            canonical_url: listing_url,
            source_url: listing_url,
            remote_text: [ "Remote", geo ].compact_blank.join(" | "),
            location_text: geo,
            description: job["jobDescription"].presence || job["jobExcerpt"].to_s,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              job_slug: job["jobSlug"],
              industry: job["jobIndustry"],
              job_type: job["jobType"],
              job_level: job["jobLevel"],
              company_logo: job["companyLogo"],
              salary_min: job["salaryMin"],
              salary_max: job["salaryMax"],
              salary_currency: job["salaryCurrency"],
              salary_period: job["salaryPeriod"]
            }
          )
        end

        # Keeps listings open to anywhere or to the candidate's own region.
        # A foreign-only list such as "USA" or "UK, Canada" is dropped here,
        # because the policy's restriction guard only recognises phrases such as
        # "USA only", not a bare region list. An empty list is treated as
        # unknown eligibility rather than as remote-for-everyone.
        def eligible_geo?(geo)
          return false if geo.blank?

          geo.match?(JobDiscovery::Policy::GLOBAL_ELIGIBILITY_PATTERNS) ||
            geo.match?(JobDiscovery::Policy::HOME_REGION_PATTERNS)
        end
    end
  end
end
