require "json"

module JobDiscovery
  module Adapters
    # Public JSON API from artificialintelligencejobs.co (documented at /developers).
    #
    # The board aggregates AI-adjacent roles and keeps the employer's real apply
    # URL, so candidates canonicalize to the original ATS posting whenever the
    # board exposes one.
    class ArtificialintelligencejobsApiAdapter < Base
      API_URL = "https://artificialintelligencejobs.co/api/jobs".freeze
      DEFAULT_PAGE_SIZE = 50
      DEFAULT_MAX_PAGES = 4
      DEFAULT_MAX_DETAIL_PAGES = 12

      def scan(source_scan:, window_days:)
        settings = source_scan.job_source.settings
        page_size = bounded(settings["page_size"], DEFAULT_PAGE_SIZE)
        max_pages = bounded(settings["max_pages"], DEFAULT_MAX_PAGES)
        cutoff = window_days.days.ago.beginning_of_day
        candidates = []
        detail_budget = bounded(settings["max_detail_pages"], DEFAULT_MAX_DETAIL_PAGES)

        max_pages.times do |page|
          source_scan.record_page!
          payload = JSON.parse(fetcher.call(page_url(page_size:, offset: page * page_size, settings:)))
          jobs = Array(payload["jobs"])
          break if jobs.empty?

          jobs.each do |job|
            candidate = build_candidate_from_job(source_scan:, job:, cutoff:, detail_budget:)
            next unless candidate

            detail_budget -= 1 if candidate.delete(:fetched_detail)
            candidates << candidate
          end

          break if jobs.size < page_size || candidates.size >= payload["matched"].to_i
        end

        candidates.uniq { |candidate| candidate.fetch(:canonical_url) }
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
          description = [ metadata_description(job, location), detail ].compact_blank.join(" | ")

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

        def detail_description(board_url)
          document = html_document(board_url)
          document.at_css("body")&.text.to_s.squish.presence
        rescue StandardError
          nil
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

        def bounded(value, fallback)
          [ value.presence&.to_i || fallback, 1 ].max
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
