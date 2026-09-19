require "json"

module JobDiscovery
  module Adapters
    # Braintrust (https://app.usebraintrust.com) is a freelance marketplace
    # whose own SPA loads its listings from a public, unauthenticated JSON API
    # (/api/jobs). The list payload carries the title, employer, locations,
    # skills and creation date but no description or status, so only titles
    # that pass the pre-filter earn a bounded detail request (/api/jobs/:id)
    # that adds the description, publish date and open/closed state.
    #
    # UNVERIFIED (2026-09-18): robots.txt only disallows crawling URLs that
    # carry query params (?page=, ?key=, utm_*...), and the companion sitemap
    # index is empty, so the API is the only listing surface. The endpoint is
    # undocumented and the terms of service were not reviewed. See README
    # "Source provenance and unverified terms".
    class BraintrustJobsApiAdapter < Base
      API_URL = "https://app.usebraintrust.com/api/jobs".freeze
      API_HOST = "app.usebraintrust.com".freeze
      DEFAULT_PAGE_SIZE = 50
      DEFAULT_MAX_PAGES = 4
      DEFAULT_MAX_DETAIL_PAGES = 12
      MAX_DESCRIPTION_CHARS = 8_000

      def scan(source_scan:, window_days:)
        settings = source_scan.job_source.settings
        page_size = bounded(settings["page_size"], DEFAULT_PAGE_SIZE)
        max_pages = bounded(settings["max_pages"], DEFAULT_MAX_PAGES)
        cutoff = window_days.days.ago.beginning_of_day
        detail_budget = bounded(settings["max_detail_pages"], DEFAULT_MAX_DETAIL_PAGES, floor: 0)
        seen_jobs = 0
        candidates = []

        max_pages.times do |page|
          source_scan.record_page!
          payload = parsed_page(page_url(page:, page_size:, settings:))
          break if payload.nil?

          jobs = Array(payload["results"])
          break if jobs.empty?

          seen_jobs += jobs.size
          jobs.each do |job|
            candidate = build_candidate_from_job(source_scan:, job:, cutoff:, detail_budget:)
            next unless candidate

            detail_budget -= 1 if candidate.delete(:fetched_detail)
            candidates << candidate
          end

          break if jobs.size < page_size
          break if reported_total(payload)&.then { |total| seen_jobs >= total }
        end

        deduped = candidates.uniq { |candidate| candidate.fetch(:external_job_id) }
        record_scan_metrics(source_scan, rows_seen: seen_jobs, candidates: candidates.size, deduped: deduped.size, detail_budget_left: detail_budget)
        deduped
      end

      private
        def build_candidate_from_job(source_scan:, job:, cutoff:, detail_budget:)
          title = job["title"].to_s.squish
          return unless title.present? && policy.potential_match?(title)

          created_at = parse_time(job["created"])
          return if created_at.present? && created_at < cutoff

          detail = detail_budget.positive? ? fetch_detail(job) : nil
          active = detail_active?(detail)

          published_at = parse_time(detail&.dig("published_at")) || created_at
          return if published_at.present? && published_at < cutoff

          external_job_id = job["id"].to_s
          apply_url = job_page_url(external_job_id)
          company_name = job.dig("employer", "name").to_s.squish.presence || "Empresa nao identificada"
          location_text = location_signal(job, detail)
          description = [
            metadata_description(job),
            description_text(detail)
          ].compact_blank.join(" | ").truncate(MAX_DESCRIPTION_CHARS, omission: "")

          decision = expired_result(reason: "vaga encerrada no Braintrust") if active == false

          candidate = build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "Braintrust",
            source_kind: source_scan.job_source.source_kind.presence || "platform",
            source_slug: source_scan.job_source.slug.presence || "braintrust",
            title:,
            company_name:,
            apply_url:,
            canonical_url: apply_url,
            source_url: apply_url,
            remote_text: remote_signal(title, location_text, detail),
            location_text:,
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id:,
            payload: {
              braintrust_id: external_job_id,
              contract_type: job["contract_type"],
              job_type: job["job_type"],
              payment_type: job["payment_type"],
              budget_usd: budget_signal(job),
              role: job.dig("role", "name"),
              skills: skills_signal(job),
              experience_required: detail&.dig("experience_level"),
              open: detail&.dig("is_open")
            },
            decision:
          )
          candidate.merge(fetched_detail: detail.present?)
        end

        def parsed_page(url)
          payload = JSON.parse(fetcher.call(url, allowed_hosts: [ API_HOST ]))
          payload.is_a?(Hash) ? payload : nil
        rescue JSON::ParserError => error
          Rails.logger.warn("[braintrust] unparseable page #{url}: #{error.message}")
          nil
        end

        def fetch_detail(job)
          id = job["id"]
          return unless id.to_s.match?(/\A\d+\z/)

          payload = JSON.parse(fetcher.call("#{API_URL}/#{id}", allowed_hosts: [ API_HOST ]))
          payload.is_a?(Hash) ? payload : nil
        rescue JobDiscovery::Fetcher::RequestError, JSON::ParserError => error
          Rails.logger.warn("[braintrust] detail fetch failed for id #{id}: #{error.class}: #{error.message}")
          nil
        end

        def detail_active?(detail)
          return nil if detail.nil?

          status = detail["job_status"].to_s.downcase
          detail["is_open"] != false && status != "closed" && status != "filled"
        end

        def metadata_description(job)
          [ job.dig("role", "name"), job["contract_type"], job["job_type"], budget_signal(job) ]
            .compact_blank.join(" | ")
        end

        def description_text(detail)
          body = detail&.fetch("description", "").to_s
          body = Nokogiri::HTML(body).text if body.include?("<")
          body.squish
        end

        def location_signal(job, detail)
          rows = Array(job["locations"].presence || detail&.fetch("locations", nil))
          rows.filter_map { |row| row.is_a?(Hash) ? (row["custom_location"] || row["location"]) : row }
            .map(&:to_s).map(&:squish).compact_blank.uniq.join(", ")
        end

        def remote_signal(title, location_text, detail)
          return "Remote" if title.to_s.match?(/remote|remoto/i)
          return "Remote" if location_text.to_s.match?(/remote|remoto/i)

          timezone_text = Array(detail&.fetch("timezones", nil)).map { |row| row["timezone"] if row.is_a?(Hash) }
            .compact.join(" ")
          timezone_text.presence || location_text.presence
        end

        def budget_signal(job)
          minimum = job["budget_minimum_usd"]
          maximum = job["budget_maximum_usd"]
          return if minimum.blank? && maximum.blank?

          [ minimum, maximum ].compact_blank.uniq.join("-")
        end

        def skills_signal(job)
          Array(job["job_skills"]).filter_map { |row| row.dig("skill", "name") if row.is_a?(Hash) }
            .compact_blank.uniq
        end

        def job_page_url(external_job_id)
          "https://app.usebraintrust.com/jobs/#{external_job_id}"
        end

        def page_url(page:, page_size:, settings:)
          query = { page: page + 1, page_size: }
          query[:role] = settings["role"] if settings["role"].to_s.present?

          "#{API_URL}?#{URI.encode_www_form(query)}"
        end

        def expired_result(reason:)
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

        def reported_total(payload)
          total = payload["count"]
          return unless total.is_a?(Numeric) || total.to_s.match?(/\A\d+\z/)

          value = total.to_i
          value.positive? ? value : nil
        end

        def bounded(value, fallback, floor: 1)
          configured = value.is_a?(Numeric) || value.to_s.match?(/A-?d+z/) ? value.to_i : nil
          [ configured || fallback, floor ].max
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
