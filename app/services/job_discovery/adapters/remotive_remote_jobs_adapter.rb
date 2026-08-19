require "json"

module JobDiscovery
  module Adapters
    # Public JSON feed from Remotive (https://remotive.com/api/remote-jobs).
    # Remotive is a remote-only job board, so every accepted posting carries a
    # "Remote" signal for the profile policy.
    class RemotiveRemoteJobsAdapter < Base
      API_URL = "https://remotive.com/api/remote-jobs".freeze

      def scan(source_scan:, window_days:)
        max_results = [ source_scan.job_source.settings.fetch("max_results", 100).to_i, 1 ].max
        cutoff = window_days.days.ago.beginning_of_day

        source_scan.record_page!
        payload = JSON.parse(fetcher.call("#{API_URL}?#{URI.encode_www_form(limit: max_results)}"))
        jobs = Array(payload["jobs"])

        jobs.filter_map do |job|
          build_candidate_from_job(source_scan:, job:, cutoff:)
        end
      end

      private
        def build_candidate_from_job(source_scan:, job:, cutoff:)
          title = job["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job["publication_date"])
          return if published_at.present? && published_at < cutoff

          url = job["url"].to_s
          return if url.blank?

          location = job["candidate_required_location"].to_s

          build_candidate(
            source_scan:,
            source_name: "Remotive",
            source_kind: "platform",
            source_slug: "remotive",
            title:,
            company_name: job["company_name"].to_s.presence || "Remotive",
            apply_url: url.delete_suffix("/"),
            canonical_url: url.delete_suffix("/"),
            source_url: url.delete_suffix("/"),
            remote_text: [ "Remote", location ].compact_blank.join(" | "),
            location_text: location,
            description: job["description"].to_s,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              category: job["category"],
              tags: job["tags"],
              job_type: job["job_type"],
              salary: job["salary"],
              company_logo_url: job["company_logo_url"]
            }
          )
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
