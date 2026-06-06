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

        def extract_apply_url(document, page_url)
          link = document.css("a[href]").find { |node| node.text.to_s.match?(/candidat|inscrev|apply/i) }
          href = link&.[]("href")
          return page_url if href.blank?

          absolute_url(page_url, href)
        end

        def build_candidate(source_scan:, source_name:, source_kind:, source_slug:, title:, company_name:, apply_url:, canonical_url:, source_url:, remote_text:, location_text:, description:, posted_text:, published_at:, external_job_id:, payload:)
          decision = policy.classify(
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
            payload:
          }
        end
    end
  end
end
