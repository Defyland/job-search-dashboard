require "json"

module JobDiscovery
  module Adapters
    class WorkableGlobalApiAdapter < Base
      API_URL = "https://jobs.workable.com/api/v1/jobs".freeze

      def scan(source_scan:, window_days:)
        page_limit = [ source_scan.job_source.settings.fetch("max_pages", default_page_limit(window_days)).to_i, 1 ].max
        next_page_token = nil
        candidates = []

        page_limit.times do
          source_scan.record_page!
          response = fetch_page(next_page_token)
          jobs = Array(response["jobs"])
          break if jobs.empty?

          jobs.each do |job|
            candidate = build_candidate_from_job(source_scan:, job:, window_days:)
            candidates << candidate if candidate
          end

          next_page_token = response["nextPageToken"].presence
          break if next_page_token.blank?
        end

        candidates
      end

      private
        def fetch_page(next_page_token)
          url = if next_page_token.present?
            "#{API_URL}?#{URI.encode_www_form(nextPageToken: next_page_token)}"
          else
            API_URL
          end

          JSON.parse(fetcher.call(url))
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

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def default_page_limit(window_days)
          window_days >= 20 ? 15 : 5
        end
    end
  end
end
