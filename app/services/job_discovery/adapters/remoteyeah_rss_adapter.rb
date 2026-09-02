module JobDiscovery
  module Adapters
    class RemoteyeahRssAdapter < Base
      FEED_URL = "https://remoteyeah.com/rss.xml".freeze
      HOST = "remoteyeah.com".freeze

      def scan(source_scan:, window_days:)
        seed_candidates = configured_seed_urls(source_scan).filter_map do |url|
          source_scan.record_page!
          build_candidate_from_page(source_scan:, url:, window_days:)
        end

        source_scan.record_page!
        feed = Nokogiri::XML(fetcher.call(feed_url(source_scan)))
        feed_candidates = feed.xpath("//item").filter_map do |item|
          build_candidate_from_item(source_scan:, item:, window_days:)
        end

        (seed_candidates + feed_candidates).uniq { |candidate| candidate.fetch(:canonical_url) }
      end

      private
        def build_candidate_from_page(source_scan:, url:, window_days:)
          document = html_document(url)
          posting = parse_job_posting_json(document)
          title = posting["title"].to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(posting["datePosted"])
          return if outside_window?(published_at, window_days)
          return if expired?(posting["validThrough"])

          description = Nokogiri::HTML.fragment(posting["description"].to_s).text.squish
          location = applicant_locations(posting)

          build_remote_candidate(
            source_scan:,
            title:,
            company_name: posting.dig("hiringOrganization", "name"),
            canonical_url: url,
            location:,
            description:,
            published_at:,
            external_job_id: external_job_id_for(url),
            payload: {
              discovery_method: "seed_url",
              valid_through: posting["validThrough"],
              employment_type: posting["employmentType"],
              skills: posting["skills"],
              direct_apply: posting["directApply"]
            }
          )
        end

        def build_candidate_from_item(source_scan:, item:, window_days:)
          title = item.at_xpath("title")&.text.to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(item.at_xpath("pubDate")&.text)
          return if outside_window?(published_at, window_days)

          canonical_url = normalized_job_url(item.at_xpath("link")&.text)
          return unless canonical_url

          description_html = item.at_xpath("description")&.text.to_s
          description = Nokogiri::HTML.fragment(description_html).text.squish
          location = item.at_xpath("location")&.text.to_s.squish
          company_name = item.at_xpath("company")&.text.to_s.squish.presence || company_name_from_title(title)

          build_remote_candidate(
            source_scan:,
            title:,
            company_name:,
            canonical_url:,
            location:,
            description:,
            published_at:,
            external_job_id: item.at_xpath("guid")&.text.to_s.squish.presence || external_job_id_for(canonical_url),
            payload: {
              discovery_method: "rss",
              feed_url: feed_url(source_scan),
              category: item.at_xpath("category")&.text.to_s.squish.presence,
              tags: item.at_xpath("tags")&.text.to_s.split(",").map(&:squish).compact_blank
            }
          )
        end

        def build_remote_candidate(source_scan:, title:, company_name:, canonical_url:, location:, description:, published_at:, external_job_id:, payload:)
          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "RemoteYeah",
            source_kind: source_scan.job_source.source_kind.presence || "platform",
            source_slug: source_scan.job_source.slug.presence || "remoteyeah",
            title:,
            company_name: company_name.to_s.squish.presence || "Empresa nao identificada",
            apply_url: canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text: [ "Remote", location ].compact_blank.join(" | "),
            location_text: location,
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id:,
            payload:
          )
        end

        def configured_seed_urls(source_scan)
          Array(source_scan.job_source.settings["seed_urls"]).filter_map { |url| normalized_job_url(url) }.uniq
        end

        def feed_url(source_scan)
          source_scan.job_source.settings["feed_url"].presence || FEED_URL
        end

        def normalized_job_url(value)
          uri = URI.parse(value.to_s.strip)
          host = uri.host.to_s.downcase.sub(/\Awww\./, "")
          return unless host == HOST && uri.path.start_with?("/jobs/")

          uri.scheme = "https"
          uri.host = HOST
          uri.query = nil
          uri.fragment = nil
          uri.to_s.delete_suffix("/")
        rescue URI::InvalidURIError
          nil
        end

        def applicant_locations(posting)
          Array(posting["applicantLocationRequirements"]).filter_map do |location|
            location["name"].to_s.squish.presence if location.respond_to?(:[])
          end.join(", ").presence
        end

        def company_name_from_title(title)
          title.to_s.split(/\s+at\s+/i).last.to_s.squish.presence
        end

        def outside_window?(published_at, window_days)
          published_at.present? && published_at < window_days.days.ago.beginning_of_day
        end

        def expired?(value)
          valid_through = parse_time(value)
          valid_through.present? && valid_through < Time.current
        end

        def external_job_id_for(url)
          URI.parse(url).path.split("/").reject(&:blank?).last.to_s.presence
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
