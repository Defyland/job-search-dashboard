require "json"
require "set"

module JobDiscovery
  module Adapters
    # Public JSON feed from Remote OK (https://remoteok.com/api).
    #
    # Note: Remote OK's API terms require attribution/link-back when the jobs
    # are displayed; keep the source visible in the dashboard.
    #
    # The unfiltered feed returns the ~100 most recent jobs across every
    # category, which matched zero target-stack roles when measured on
    # 2026-09-04. The endpoint accepts a `tag` parameter, and one request per
    # configured tag returned 277 unique jobs, all carrying a target stack.
    class RemoteokJobsApiAdapter < Base
      API_URL = "https://remoteok.com/api".freeze
      DEFAULT_TAGS = %w[ruby rails golang elixir react].freeze
      MAX_TAGS = 8

      def scan(source_scan:, window_days:)
        cutoff = window_days.days.ago.beginning_of_day
        seen_ids = Set.new

        configured_tags(source_scan).flat_map do |tag|
          source_scan.record_page!
          JSON.parse(fetcher.call(tag_url(tag))).filter_map do |job|
            next if job["position"].blank? # first payload entry is the API notice object
            # The same vacancy is tagged both "ruby" and "rails", so it must
            # only be built once.
            next unless seen_ids.add?(job["id"].to_s)

            build_candidate_from_job(source_scan:, job:, cutoff:)
          end
        end
      end

      private
        def tag_url(tag)
          tag.present? ? "#{API_URL}?#{URI.encode_www_form(tag:)}" : API_URL
        end

        def configured_tags(source_scan)
          settings = source_scan.job_source.settings
          return DEFAULT_TAGS unless settings.key?("tags")

          tags = Array(settings["tags"]).map { |value| value.to_s.squish }.reject(&:blank?)
          # An explicitly empty list asks for the unfiltered feed; nil is the
          # "no tag parameter" marker.
          return [ nil ] if tags.blank?

          tags.uniq.first(MAX_TAGS)
        end

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
