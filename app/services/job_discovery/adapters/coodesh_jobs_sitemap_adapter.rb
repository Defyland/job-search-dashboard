require "cgi"
require "json"

module JobDiscovery
  module Adapters
    class CoodeshJobsSitemapAdapter < Base
      HOST = "coodesh.com".freeze
      SITEMAP_URL = "https://coodesh.com/sitemaps/jobs.xml".freeze
      JOB_MARKER = "\\\"job\\\":{".freeze

      def scan(source_scan:, window_days:)
        job_urls = fetch_job_urls(source_scan)

        job_urls.filter_map do |job_url|
          source_scan.record_page!
          build_candidate_from_job_page(source_scan:, job_url:, window_days:)
        end
      end

      private
        def fetch_job_urls(source_scan)
          source_scan.record_page!

          configured = Array(source_scan.job_source.settings["job_urls"])
          discovered = known_hosted_urls(host_suffixes: [ HOST ]).select { |url| coodesh_job_url?(url) }
          sitemap_urls = fetcher.call(SITEMAP_URL).scan(%r{<loc>(https://coodesh\.com/jobs/[^<]+)</loc>}i).flatten

          (configured + discovered + sitemap_urls).map { |url| canonical_url_string(url) }.reject(&:blank?).uniq
        end

        def build_candidate_from_job_page(source_scan:, job_url:, window_days:)
          html = fetcher.call(job_url)
          job_payload = extract_job_payload(html)
          return if job_payload.blank?

          title = job_payload["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_time(job_payload["publish_date"]) || parse_time(job_payload["created"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          company_name = job_payload.dig("company", "company_name").presence || company_name_for_url(job_url) || "Coodesh"
          canonical_url = canonical_url_string(job_url)

          build_candidate(
            source_scan:,
            source_name: "Coodesh",
            source_kind: "platform",
            source_slug: "coodesh",
            title:,
            company_name:,
            apply_url: extract_apply_url(job_payload, canonical_url),
            canonical_url:,
            source_url: canonical_url,
            remote_text: remote_signal(job_payload),
            location_text: location_signal(job_payload),
            description: normalized_description(job_payload),
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job_payload["_id"].presence || job_payload["slug"].presence,
            payload: {
              application_type: job_payload["application_type"],
              external_url: job_payload["external_url"],
              type_formatted: job_payload["type_formatted"],
              level_formatted: job_payload["level_formatted"],
              home_office_formatted: job_payload["home_office_formatted"],
              status_formatted: job_payload["status_formatted"],
              salary_range_formatted: job_payload["salary_range_formatted"],
              skills: Array(job_payload["skills"]).filter_map { |skill| skill["name"] }
            }
          )
        end

        def coodesh_job_url?(url)
          uri = URI.parse(url)
          normalized_host(url) == HOST && uri.path.start_with?("/jobs/")
        rescue URI::InvalidURIError
          false
        end

        def extract_job_payload(html)
          marker_index = html.index(JOB_MARKER)
          return {} unless marker_index

          json_object = decode_embedded_json_object(html, marker_index + JOB_MARKER.length - 1)
          return {} if json_object.blank?

          JSON.parse(json_object)
        rescue JSON::ParserError
          {}
        end

        def decode_embedded_json_object(html, start_index)
          decoded = +""
          depth = 0
          in_string = false
          index = start_index

          while index < html.length
            char = html[index]

            if char == "\\"
              index += 1
              break if index >= html.length

              escaped = html[index]
              decoded << decode_escape_sequence(html, escaped, index)
              in_string = !in_string if escaped == "\""
              index += 4 if escaped == "u"
            else
              decoded << char

              if char == "\""
                in_string = !in_string
              elsif !in_string
                depth += 1 if char == "{"

                if char == "}"
                  depth -= 1
                  return decoded if depth.zero?
                end
              end
            end

            index += 1
          end

          nil
        end

        def decode_escape_sequence(html, escaped, index)
          case escaped
          when "\"", "\\", "/"
            escaped
          when "b"
            "\b"
          when "f"
            "\f"
          when "n"
            "\n"
          when "r"
            "\r"
          when "t"
            "\t"
          when "u"
            hex = html[(index + 1), 4]
            [ hex.to_i(16) ].pack("U")
          else
            escaped
          end
        end

        def extract_apply_url(job_payload, canonical_url)
          external_url = canonical_url_string(job_payload["external_url"])
          external_url.presence || canonical_url
        end

        def normalized_description(job_payload)
          fragments = [
            job_payload["description"],
            Array(job_payload["requirements"]),
            Array(job_payload["differentials"]),
            Array(job_payload["benefits"]),
            Array(job_payload["skills"]).filter_map { |skill| skill["name"] }
          ].flatten.compact

          Nokogiri::HTML.fragment(CGI.unescapeHTML(fragments.join(" "))).text.squish
        end

        def remote_signal(job_payload)
          job_payload["home_office_formatted"].presence || job_payload["home_office"].to_s.humanize
        end

        def location_signal(job_payload)
          company_address = job_payload.dig("company", "address").to_h

          company_address["full_location"].presence || [
            company_address["city"],
            company_address["province"],
            company_address["country"]
          ].compact_blank.join(", ")
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
