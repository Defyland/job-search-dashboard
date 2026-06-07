require "cgi"
require "json"

module JobDiscovery
  module Adapters
    class Base
      URL_COLUMNS = %i[canonical_url source_url apply_url].freeze

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

        def known_hosted_urls(host_suffixes:)
          host_suffixes = normalized_host_suffixes(host_suffixes)
          return [] if host_suffixes.empty?

          @known_hosted_urls_by_suffix ||= {}
          @known_hosted_urls_by_suffix[host_suffixes.sort.join("|")] ||= Job.active
            .where(host_suffix_predicate(host_suffixes))
            .pluck(*URL_COLUMNS)
            .flatten
            .compact
            .map { |url| canonical_url_string(url) }
            .select { |url| hosted_url?(url, host_suffixes) }
            .uniq
        end

        def company_name_for_url(url)
          normalized_url = canonical_url_string(url)
          return if normalized_url.blank?

          @company_name_by_url ||= {}
          return @company_name_by_url[normalized_url] if @company_name_by_url.key?(normalized_url)

          url_variants = [ normalized_url, "#{normalized_url}/" ].uniq
          @company_name_by_url[normalized_url] = Job.active
            .where(url_exact_predicate(url_variants))
            .pick(:company_name)
            &.squish
            &.presence
        end

        def normalized_host(url)
          URI.parse(url.to_s).host.to_s.downcase.sub(/\Awww\./, "")
        rescue URI::InvalidURIError
          ""
        end

        def canonical_url_string(url)
          url.to_s.strip.delete_suffix("/")
        end

        def normalized_host_suffixes(host_suffixes)
          Array(host_suffixes).filter_map do |suffix|
            normalized = suffix.to_s.downcase.strip
            normalized = normalized.delete_prefix("https://").delete_prefix("http://")
            normalized = normalized.delete_suffix("/").delete_prefix("www.").delete_prefix(".")
            normalized if normalized.match?(/\A[a-z0-9.-]+\z/)
          end.uniq
        end

        def hosted_url?(url, host_suffixes)
          host = normalized_host(url)
          host.present? && host_suffixes.any? { |suffix| host == suffix || host.end_with?(".#{suffix}") }
        end

        def host_suffix_predicate(host_suffixes)
          table = Job.arel_table
          predicates = host_suffixes.flat_map do |suffix|
            [ "%://#{suffix}%", "%://%.#{suffix}%" ].flat_map do |pattern|
              URL_COLUMNS.map do |column|
                Arel::Nodes::NamedFunction.new("LOWER", [ table[column] ]).matches(pattern)
              end
            end
          end

          predicates.reduce { |left, right| left.or(right) }
        end

        def url_exact_predicate(url_variants)
          table = Job.arel_table
          URL_COLUMNS.map { |column| table[column].in(url_variants) }.reduce { |left, right| left.or(right) }
        end
    end
  end
end
