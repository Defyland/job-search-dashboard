module JobDiscovery
  module Adapters
    # Public RSS feeds from We Work Remotely (https://weworkremotely.com/remote-job-rss-feed).
    #
    # Note: WWR asks aggregators to attribute links back to the original job
    # post, so the canonical URL always stays on weworkremotely.com.
    class WeworkremotelyRssAdapter < Base
      HOST = "weworkremotely.com".freeze
      DEFAULT_FEED_URLS = [
        "https://weworkremotely.com/categories/remote-programming-jobs.rss",
        "https://weworkremotely.com/categories/remote-full-stack-programming-jobs.rss",
        "https://weworkremotely.com/categories/remote-back-end-programming-jobs.rss",
        "https://weworkremotely.com/categories/remote-front-end-programming-jobs.rss"
      ].freeze

      def scan(source_scan:, window_days:)
        feed_urls(source_scan).flat_map do |feed_url|
          source_scan.record_page!
          feed = Nokogiri::XML(fetcher.call(feed_url))

          feed.xpath("//item").filter_map do |item|
            build_candidate_from_item(source_scan:, item:, feed_url:, window_days:)
          end
        end.uniq { |candidate| candidate.fetch(:canonical_url) }
      end

      private
        def build_candidate_from_item(source_scan:, item:, feed_url:, window_days:)
          raw_title = node_text(item, "title")
          company_name, title = split_company_and_title(raw_title)
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(node_text(item, "pubDate"))
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day
          return if expired?(node_text(item, "expires_at"))

          canonical_url = normalized_job_url(node_text(item, "link").presence || node_text(item, "guid"))
          return unless canonical_url

          description = Nokogiri::HTML.fragment(node_text(item, "description")).text.squish
          region = node_text(item, "region")

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "We Work Remotely",
            source_kind: source_scan.job_source.source_kind.presence || "platform",
            source_slug: source_scan.job_source.slug.presence || "weworkremotely",
            title:,
            company_name: company_name.presence || "Empresa nao identificada",
            apply_url: canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text: [ "Remote", region ].compact_blank.join(" | "),
            location_text: location_signal(item, region),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: external_job_id_for(canonical_url),
            payload: {
              feed_url:,
              category: node_text(item, "category").presence,
              employment_type: node_text(item, "type").presence,
              region: region.presence,
              skills: node_text(item, "skills").split(",").map(&:squish).compact_blank,
              expires_at: node_text(item, "expires_at").presence
            }
          )
        end

        def feed_urls(source_scan)
          configured = Array(source_scan.job_source.settings["feed_urls"]).map { |url| url.to_s.strip }.compact_blank
          (configured.presence || DEFAULT_FEED_URLS).uniq
        end

        # WWR titles are published as "Company: Role", so the company prefix has
        # to be split off before the policy sees the role title.
        def split_company_and_title(raw_title)
          company, separator, role = raw_title.to_s.partition(":")
          return [ nil, raw_title.to_s.squish ] if separator.blank? || role.squish.blank?

          [ company.squish, role.squish ]
        end

        def location_signal(item, region)
          [ node_text(item, "country"), node_text(item, "state"), region ].compact_blank.map(&:squish).uniq.join(", ")
        end

        def normalized_job_url(value)
          uri = URI.parse(value.to_s.strip)
          return unless normalized_host(uri.to_s) == HOST && uri.path.start_with?("/remote-jobs/")

          uri.scheme = "https"
          uri.query = nil
          uri.fragment = nil
          canonical_url_string(uri.to_s)
        rescue URI::InvalidURIError
          nil
        end

        def expired?(value)
          expires_at = parse_time(value)
          expires_at.present? && expires_at < Time.current
        end

        def node_text(item, name)
          item.at_xpath(name)&.text.to_s
        end

        def external_job_id_for(url)
          URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s.presence
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
