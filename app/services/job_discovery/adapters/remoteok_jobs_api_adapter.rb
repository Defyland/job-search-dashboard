require "json"

module JobDiscovery
  module Adapters
    # Public JSON feed from Remote OK (https://remoteok.com/api).
    #
    # Note: Remote OK's API terms require attribution/link-back when the jobs
    # are displayed; keep the source visible in the dashboard.
    class RemoteokJobsApiAdapter < Base
      API_URL = "https://remoteok.com/api".freeze

      def scan(source_scan:, window_days:)
        source_scan.record_page!
        payload = JSON.parse(fetcher.call(API_URL))
        cutoff = window_days.days.ago.beginning_of_day

        payload.filter_map do |job|
          next if job["position"].blank? # first payload entry is the API notice object

          build_candidate_from_job(source_scan:, job:, cutoff:)
        end
      end

      private
        def build_candidate_from_job(source_scan:, job:, cutoff:)
          title = job["position"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job["date"]) || epoch_time(job["epoch"])
          return if published_at.present? && published_at < cutoff

          apply_url = job["apply_url"].presence || job["url"].to_s
          canonical_url = job["url"].to_s
          return if apply_url.blank? || canonical_url.blank?

          build_candidate(
            source_scan:,
            source_name: "RemoteOK",
            source_kind: "platform",
            source_slug: "remoteok",
            title:,
            company_name: job["company"].to_s.presence || "RemoteOK",
            apply_url: apply_url.delete_suffix("/"),
            canonical_url: canonical_url.delete_suffix("/"),
            source_url: canonical_url.delete_suffix("/"),
            remote_text: [ "Remote", job["location"].to_s ].compact_blank.join(" | "),
            location_text: job["location"].to_s,
            description: job["description"].to_s,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              slug: job["slug"],
              tags: job["tags"],
              salary_min: job["salary_min"],
              salary_max: job["salary_max"],
              salary_currency: job["salary_currency"],
              company_logo: job["company_logo"],
              epoch: job["epoch"]
            }
          )
        end

        def epoch_time(value)
          Time.zone.at(Integer(value)) if value.present?
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
