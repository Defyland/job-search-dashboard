require "cgi"

module JobDiscovery
  module Adapters
    class RailsfullstackJobsSitemapAdapter < Base
      HOST = "railsfullstack.com".freeze
      SITEMAP_URL = "https://www.railsfullstack.com/sitemap.xml".freeze
      COLLECTION_URL = "https://www.railsfullstack.com/collections/remote-full-stack-rails-jobs".freeze
      DEFAULT_MAX_JOBS = 40

      def scan(source_scan:, window_days:)
        max_jobs = [ source_scan.job_source.settings.fetch("max_jobs", DEFAULT_MAX_JOBS).to_i, 1 ].max
        collection_candidates = collection_urls(source_scan).flat_map do |collection_url|
          source_scan.record_page!
          build_candidates_from_collection(source_scan:, collection_url:, window_days:, max_jobs:)
        end
        return collection_candidates.uniq { |candidate| candidate.fetch(:canonical_url) } if collection_candidates.any?

        references = fetch_job_references(source_scan)
        references.first(max_jobs).filter_map do |reference|
          source_scan.record_page!
          build_candidate_from_page(source_scan:, reference:, window_days:)
        end.uniq { |candidate| candidate.fetch(:canonical_url) }
      end

      private
        def build_candidates_from_collection(source_scan:, collection_url:, window_days:, max_jobs:)
          document = html_document(collection_url)
          payload = JSON.parse(document.at_css("#app[data-page]")&.[]("data-page").to_s)

          Array(payload.dig("props", "jobs")).first(max_jobs).filter_map do |job|
            build_candidate_from_collection_job(source_scan:, job:, window_days:)
          end
        rescue JSON::ParserError
          []
        end

        def build_candidate_from_collection_job(source_scan:, job:, window_days:)
          return if job["hidden"]

          title = job["title"].to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(job["posted_at"] || job["created_at"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          canonical_url = normalize_job_url("https://#{HOST}/jobs/#{job['slug']}")
          return unless canonical_url

          location = job["location"].to_s.squish
          remote_text = [ job["remote_type"], location ].compact_blank.join(" | ")

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "RailsFullstack",
            source_kind: source_scan.job_source.source_kind.presence || "platform",
            source_slug: source_scan.job_source.slug.presence || "railsfullstack",
            title:,
            company_name: job["company"].to_s.squish.presence || "RailsFullstack",
            apply_url: job["external_apply_url"].presence || job["apply_url"].presence || canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text:,
            location_text: location,
            description: normalized_description(job["description"]),
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s.presence || job["slug"].to_s.presence,
            payload: {
              discovery_method: "collection",
              tags: job["tags"],
              architecture: job["architecture"],
              salary_display: job["salary_display"],
              source: job["source"],
              last_seen_at: job["last_seen_at"],
              apply_links: job["apply_links"]
            }
          )
        end

        def collection_urls(source_scan)
          Array(source_scan.job_source.settings.fetch("collection_urls", [ COLLECTION_URL ]))
        end

        def fetch_job_references(source_scan)
          sitemap_url = source_scan.job_source.settings["sitemap_url"].presence || SITEMAP_URL
          source_scan.record_page!
          sitemap = Nokogiri::XML(fetcher.call(sitemap_url))

          if sitemap.at_xpath("//*[local-name()='sitemapindex']")
            job_sitemap_urls(sitemap).flat_map do |job_sitemap_url|
              source_scan.record_page!
              parse_job_references(Nokogiri::XML(fetcher.call(job_sitemap_url)))
            end
          else
            parse_job_references(sitemap)
          end
            .uniq { |reference| reference.fetch(:url) }
            .sort_by { |reference| [ -(reference[:lastmod]&.to_i || 0), reference.fetch(:sequence) ] }
        end

        def job_sitemap_urls(sitemap)
          urls = sitemap.xpath("//*[local-name()='sitemap']/*[local-name()='loc']").filter_map do |node|
            normalize_sitemap_url(node.text)
          end
          matching = urls.select { |url| url.match?(%r{/sitemaps?/.*jobs}i) }
          matching.presence || urls
        end

        def parse_job_references(sitemap)
          sitemap.xpath("//*[local-name()='url']").each_with_index.filter_map do |node, sequence|
            url = node.at_xpath("./*[local-name()='loc']")&.text
            normalized_url = normalize_job_url(url)
            next unless normalized_url

            {
              url: normalized_url,
              lastmod: parse_time(node.at_xpath("./*[local-name()='lastmod']")&.text),
              sequence:
            }
          end
        end

        def build_candidate_from_page(source_scan:, reference:, window_days:)
          document = html_document(reference.fetch(:url))
          posting = parse_job_posting_json(document)
          title = posting["title"].to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(posting["datePosted"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          canonical_url = normalize_job_url(posting["url"]) || canonical_link(document) || reference.fetch(:url)
          apply_url = extract_apply_url(document, canonical_url)
          description = normalized_description(posting["description"])
          valid_through = parse_time(posting["validThrough"])
          decision = expired_result if valid_through.present? && valid_through < Time.current

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "RailsFullstack",
            source_kind: source_scan.job_source.source_kind.presence || "platform",
            source_slug: source_scan.job_source.slug.presence || "railsfullstack",
            title:,
            company_name: posting.dig("hiringOrganization", "name").to_s.squish.presence || "RailsFullstack",
            apply_url:,
            canonical_url:,
            source_url: canonical_url,
            remote_text: remote_signal(posting, description),
            location_text: location_signal(posting),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: identifier_value(posting).presence || external_job_id_for(canonical_url),
            payload: {
              sitemap_lastmod: reference[:lastmod],
              valid_through: posting["validThrough"],
              direct_apply: posting["directApply"],
              employment_type: posting["employmentType"],
              job_location_type: posting["jobLocationType"],
              applicant_location_requirements: posting["applicantLocationRequirements"]
            },
            decision:
          )
        end

        def canonical_link(document)
          document.css("link[rel='canonical']").filter_map { |node| normalize_job_url(node["href"]) }.first
        end

        def normalize_sitemap_url(value)
          uri = URI.parse(value.to_s.strip)
          return unless normalized_host(uri.to_s) == HOST

          uri.scheme = "https"
          uri.query = nil
          uri.fragment = nil
          canonical_url_string(uri.to_s)
        rescue URI::InvalidURIError
          nil
        end

        def normalize_job_url(value)
          uri = URI.parse(value.to_s.strip)
          return unless normalized_host(uri.to_s) == HOST && uri.path.start_with?("/jobs/")

          uri.scheme = "https"
          uri.query = nil
          uri.fragment = nil
          canonical_url_string(uri.to_s)
        rescue URI::InvalidURIError
          nil
        end

        def location_signal(posting)
          locations = location_entries(posting["applicantLocationRequirements"]) + location_entries(posting["jobLocation"])
          names = locations.filter_map do |location|
            if location.is_a?(Hash)
              location["name"].presence || location.dig("address", "addressLocality").presence ||
                location.dig("address", "addressCountry").presence
            else
              location.to_s.squish.presence
            end
          end

          names.map(&:to_s).map(&:squish).reject(&:blank?).uniq.join(", ")
        end

        def location_entries(value)
          value.is_a?(Array) ? value : [ value ].compact
        end

        def remote_signal(posting, description)
          job_location_type = posting["jobLocationType"].to_s
          return "Remote" if job_location_type.match?(/telecommute|remote/i)

          description.to_s[/\b(?:fully\s+remote|remote[-\s]?first|100%\s+remote|remote|remoto)\b/i]&.squish
        end

        def normalized_description(value)
          Nokogiri::HTML.fragment(CGI.unescapeHTML(value.to_s)).text.squish
        end

        def identifier_value(posting)
          identifier = posting["identifier"]
          return identifier.to_s.squish if identifier.is_a?(String)

          identifier.to_h["value"].to_s.squish
        end

        def external_job_id_for(url)
          URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s.presence
        rescue URI::InvalidURIError
          nil
        end

        def expired_result
          reason = "vaga fora da validade no RailsFullstack"
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
    end
  end
end
