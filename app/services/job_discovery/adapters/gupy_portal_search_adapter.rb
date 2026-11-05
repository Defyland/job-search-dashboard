require "set"

module JobDiscovery
  module Adapters
    # Search endpoint behind the Gupy job portal (https://portal.gupy.io/api/job-search/jobs).
    #
    # The terms are the target stacks of the active profiles the scan runs for. Each term is paged
    # with limit/offset, at most three terms and three pages per term, so one scan makes at most nine
    # requests. Successive scans of a source rotate through the terms; the terms left out and the
    # terms whose pages ran out are recorded in the scan's metadata. A page shorter than the limit
    # ends its term. `pagination.total` is not trusted, since it can disagree with the data returned.
    # A 400 ends only the term that caused it.
    #
    # Listings are not opened: the search payload already carries the description, location and
    # workplace type, and the canonical URL is built from the listing's own Gupy company host.
    class GupyPortalSearchAdapter < Base
      API_URL = "https://portal.gupy.io/api/job-search/jobs".freeze
      DEFAULT_WORKPLACE_TYPE = "remote".freeze
      LIMIT = 100
      MAX_TERMS = 3
      MAX_PAGES = 3
      COMPANY_HOST_PATTERN = /\A[a-z0-9][a-z0-9-]*\.gupy\.io\z/
      NON_COMPANY_LABELS = %w[portal www].freeze

      def scan(source_scan:, window_days:)
        settings = source_scan.job_source.settings
        workplace_type = settings.fetch("workplace_type", DEFAULT_WORKPLACE_TYPE).to_s.squish.presence || DEFAULT_WORKPLACE_TYPE
        cutoff = window_days.days.ago.beginning_of_day
        seen_ids = Set.new
        candidates = []
        terms = search_terms
        batch = term_batch(terms, source_scan)
        truncated = []

        batch.each do |term|
          exhausted = false

          MAX_PAGES.times do |page|
            source_scan.record_page!
            jobs = search_page(term:, workplace_type:, offset: page * LIMIT)
            # A 400 means this term was rejected; the other terms still run.
            if jobs.nil?
              exhausted = true
              break
            end

            jobs.each do |job|
              # The same listing can match several terms, so it is only built once.
              next unless seen_ids.add?(job["id"].to_s)

              candidate = build_candidate_from_job(source_scan:, term:, job:, cutoff:)
              candidates << candidate if candidate
            end

            if jobs.size < LIMIT
              exhausted = true
              break
            end
          end

          truncated << term unless exhausted
        end

        record_search_terms!(source_scan:, terms:, batch:, truncated:)
        candidates
      end

      private
        def search_terms
          policy.profiles.flat_map { |profile| Array(profile.target_stacks) }
            .map { |term| term.to_s.squish.downcase }
            .reject(&:blank?)
            .uniq
        end

        # Every scan of the source takes the next MAX_TERMS terms after the previous scan's, wrapping
        # around, so a source with more stacks than one scan can search reaches all of them over time.
        def term_batch(terms, source_scan)
          return terms if terms.size <= MAX_TERMS

          start = (previous_scan_count(source_scan) * MAX_TERMS) % terms.size
          terms.rotate(start).first(MAX_TERMS)
        end

        def previous_scan_count(source_scan)
          source_scan.job_source.source_scans.where("source_scans.id < ?", source_scan.id).count
        end

        def record_search_terms!(source_scan:, terms:, batch:, truncated:)
          source_scan.update!(
            metadata: source_scan.metadata.to_h.merge(
              "search_terms" => { "searched" => batch, "pending" => terms - batch, "truncated" => truncated }
            )
          )
        end

        def search_page(term:, workplace_type:, offset:)
          payload = JSON.parse(fetcher.call(search_url(term:, workplace_type:, offset:)))
          Array(payload["data"])
        rescue JobDiscovery::Fetcher::RequestError => error
          raise unless error.code == 400

          nil
        end

        def search_url(term:, workplace_type:, offset:)
          "#{API_URL}?#{URI.encode_www_form(jobName: term, workplaceType: workplace_type, limit: LIMIT, offset:)}"
        end

        def build_candidate_from_job(source_scan:, term:, job:, cutoff:)
          title = job["name"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job["publishedDate"])
          return if published_at.present? && published_at < cutoff

          canonical_url = canonical_job_url(job)
          return if canonical_url.nil?

          location_text = [ job["city"], job["state"] ].map { |value| value.to_s.squish }.compact_blank.join(", ").presence
          workplace_type = job["workplaceType"].to_s.squish

          build_candidate(
            source_scan:,
            source_name: "Gupy Portal",
            source_kind: "ats",
            source_slug: "gupy-portal",
            title:,
            company_name: job["careerPageName"].to_s.squish.presence || "Gupy",
            apply_url: canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text: [ workplace_type, location_text ].compact_blank.join(" | "),
            location_text:,
            description: job["description"].to_s,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              search_term: term,
              workplace_type: job["workplaceType"],
              career_page_name: job["careerPageName"],
              career_page_url: job["careerPageUrl"].presence,
              job_type: job["type"],
              application_deadline: job["applicationDeadline"],
              job_url: job["jobUrl"]
            }
          )
        end

        # The listing's own host is the only trustworthy company host: the portal's `jobUrl` is
        # `https://<company>.gupy.io/job/<token>`, and the `/jobs/<id>` page is the canonical form.
        def canonical_job_url(job)
          id = job["id"].to_s
          return unless id.match?(/\A\d+\z/)

          host = company_host(job["jobUrl"])
          return if host.nil?

          "https://#{host}/jobs/#{id}"
        end

        def company_host(job_url)
          uri = URI.parse(job_url.to_s)
          host = uri.host.to_s.downcase
          return unless uri.scheme == "https"
          return unless host.match?(COMPANY_HOST_PATTERN)
          return if NON_COMPANY_LABELS.include?(host.split(".").first)

          host
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
