require "cgi"
require "json"

module JobDiscovery
  module Adapters
    class Base
      def initialize(fetcher: JobDiscovery::Fetcher.new, policy: JobDiscovery::Policy.new)
        @fetcher = fetcher
        @policy = policy
      end

      private
        attr_reader :fetcher, :policy

        def html_document(url)
          Nokogiri::HTML(fetcher.call(url))
        end

        def absolute_url(base_url, href)
          URI.join(base_url, href).to_s.delete_suffix("/")
        end

        def parse_job_posting_json(document)
          script = document.css("script[type='application/ld+json']").find { |node| node.text.include?("JobPosting") }
          return {} unless script

          parsed = JSON.parse(CGI.unescapeHTML(script.text))
          parsed.is_a?(Array) ? parsed.find { |item| item["@type"] == "JobPosting" }.to_h : parsed
        rescue JSON::ParserError
          {}
        end

        def parse_window_app_data(document)
          script = document.css("script").find { |node| node.text.include?("window.__appData =") }
          return {} unless script

          payload = script.text[/window\.__appData\s*=\s*(\{.*\})\s*;\s*(?:fetch\(|\z)/m, 1]
          return {} if payload.blank?

          JSON.parse(CGI.unescapeHTML(payload))
        rescue JSON::ParserError
          {}
        end

        def extract_apply_url(document, page_url)
          link = document.css("a[href]").find { |node| node.text.to_s.match?(/candidat|inscrev|apply/i) }
          href = link&.[]("href")
          return page_url if href.blank?

          absolute_url(page_url, href)
        end

        def build_candidate(source_scan:, source_name:, source_kind:, source_slug:, title:, company_name:, apply_url:, canonical_url:, source_url:, remote_text:, location_text:, description:, posted_text:, published_at:, external_job_id:, payload:, decision: nil)
          decision ||= policy.classify(
            title:,
            remote_text:,
            location_text:,
            description:,
            source_slug:,
            posted_text:,
            published_at:
          )

          {
            source_scan:,
            source_name:,
            source_kind:,
            source_slug:,
            title:,
            company_name:,
            apply_url:,
            canonical_url:,
            source_url:,
            remote_text:,
            location_text:,
            description:,
            posted_text:,
            published_at:,
            external_job_id:,
            fingerprint: [
              company_name,
              title,
              URI.parse(canonical_url).host,
              external_job_id
            ].map { |value| value.to_s.downcase.squish }.reject(&:blank?).join("::"),
            classification: decision.classification.to_s,
            reason: decision.reason,
            exclusion_reason: decision.exclusion_reason,
            score: decision.score,
            seniority: decision.seniority,
            stack_tags: decision.stack_tags,
            eligibility_flags: decision.eligibility_flags,
            payload:
          }
        end

        def known_job_rows
          @known_job_rows ||= Job.active.pluck(:company_name, :canonical_url, :source_url, :apply_url)
        end

        def known_urls
          @known_urls ||= known_job_rows.flat_map { |row| row.last(3) }
                                       .compact
                                       .map { |url| canonical_url_string(url) }
                                       .reject(&:blank?)
                                       .uniq
        end

        def known_company_name_map
          @known_company_name_map ||= known_job_rows.each_with_object({}) do |row, result|
            company_name = row.first.to_s.squish
            next if company_name.blank?

            row.last(3).compact.each do |url|
              normalized_url = canonical_url_string(url)
              next if normalized_url.blank?

              result[normalized_url] ||= company_name
            end
          end
        end

        def known_hosted_urls(host_suffixes:)
          known_urls.select do |url|
            host = normalized_host(url)
            host.present? && host_suffixes.any? { |suffix| host == suffix || host.end_with?(".#{suffix}") }
          end
        end

        def company_name_for_url(url)
          known_company_name_map[canonical_url_string(url)]
        end

        def normalized_host(url)
          URI.parse(url.to_s).host.to_s.downcase.sub(/\Awww\./, "")
        rescue URI::InvalidURIError
          ""
        end

        def canonical_url_string(url)
          url.to_s.strip.delete_suffix("/")
        end
    end
  end
end
