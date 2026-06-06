require "json"

module JobDiscovery
  module Adapters
    class RemotarJobsApiAdapter < Base
      API_URL = "https://api.remotar.com.br/jobs?active=true".freeze

      def scan(source_scan:, window_days:)
        page_limit = [ source_scan.job_source.settings.fetch("max_pages", default_page_limit(window_days)).to_i, 1 ].max
        candidates = []
        current_page = 1
        last_page = nil

        while current_page <= page_limit && (last_page.nil? || current_page <= last_page)
          source_scan.record_page!
          response = fetch_page(current_page)
          last_page = response.dig("meta", "last_page").to_i if response["meta"].present?
          jobs = Array(response["data"])
          break if jobs.empty?

          jobs.each do |job|
            candidate = build_candidate_from_job(source_scan:, job:, window_days:)
            candidates << candidate if candidate
          end

          current_page += 1
        end

        candidates
      end

      private
        def fetch_page(page)
          JSON.parse(fetcher.call("#{API_URL}&page=#{page}"))
        end

        def build_candidate_from_job(source_scan:, job:, window_days:)
          return unless job["active"] == true

          title = job["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job["updatedAt"]) || parse_time(job["createdAt"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          apply_url = job["externalLink"].presence
          return if apply_url.blank?

          remote_text = job["type"].to_s == "remote" ? "Remoto" : job["type"].to_s.humanize
          location_text = [ job["city"], extract_location_name(job["state"]), extract_location_name(job["country"]) ].compact_blank.join(", ")
          description = [ job["subtitle"], job["description"], Array(job["jobRequirements"]).map { |requirement| requirement["description"] } ].flatten.compact.join(" ")

          build_candidate(
            source_scan:,
            source_name: "Remotar",
            source_kind: "platform",
            source_slug: "remotar",
            title:,
            company_name: job.dig("company", "name").presence || job["companyDisplayName"].presence || "Remotar",
            apply_url:,
            canonical_url: apply_url.to_s.delete_suffix("/"),
            source_url: apply_url.to_s.delete_suffix("/"),
            remote_text:,
            location_text:,
            description:,
            posted_text: published_at ? "atualizada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              integration_source: job["integrationSource"],
              remotar_job_id: job["id"],
              external_link: job["externalLink"],
              company_link: job.dig("company", "link")
            }
          )
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def extract_location_name(value)
          case value
          when Hash
            value["name"].presence
          else
            value.to_s.presence
          end
        end

        def default_page_limit(window_days)
          window_days >= 20 ? 8 : 3
        end
    end
  end
end
