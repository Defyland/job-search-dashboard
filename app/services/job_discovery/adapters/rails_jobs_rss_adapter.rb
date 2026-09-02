module JobDiscovery
  module Adapters
    class RailsJobsRssAdapter < Base
      FEED_URL = "https://jobs.rubyonrails.org/jobs.rss".freeze

      def scan(source_scan:, window_days:)
        source_scan.record_page!
        document = Nokogiri::XML(fetcher.call(feed_url(source_scan)))

        document.xpath("//item").filter_map do |item|
          build_candidate_from_item(source_scan:, item:, window_days:)
        end
      end

      private
        def build_candidate_from_item(source_scan:, item:, window_days:)
          title = item.at_xpath("title")&.text.to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(item.at_xpath("pubDate")&.text)
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          canonical_url = canonical_url_string(item.at_xpath("link")&.text)
          return if canonical_url.blank?

          description_html = item.at_xpath("description")&.text.to_s
          description_document = Nokogiri::HTML.fragment(description_html)
          description = description_document.text.squish
          apply_url = extracted_apply_url(description_document, canonical_url)

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "Rails Job Board",
            source_kind: source_scan.job_source.source_kind.presence || "platform",
            source_slug: source_scan.job_source.slug.presence || "rails-job-board",
            title:,
            company_name: company_name_from_title(title),
            apply_url:,
            canonical_url:,
            source_url: canonical_url,
            remote_text: remote_signal(description),
            location_text: location_signal(description),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: external_job_id_for(canonical_url),
            payload: {
              feed_url: feed_url(source_scan),
              rss_guid: item.at_xpath("guid")&.text.to_s.squish
            }
          )
        end

        def feed_url(source_scan)
          source_scan.job_source.settings["feed_url"].presence || FEED_URL
        end

        def company_name_from_title(title)
          title.to_s.split(/\s+at\s+/i).last.to_s.squish.presence || "Empresa nao identificada"
        end

        def extracted_apply_url(document, canonical_url)
          href = document.css("a[href]").reverse.find { |anchor| anchor.text.match?(/apply|candidat/i) }&.[]("href")
          href.present? ? absolute_url(canonical_url, href) : canonical_url
        rescue URI::InvalidURIError
          canonical_url
        end

        def remote_signal(description)
          description.to_s[/\b(?:fully\s+remote|remote[-\s]?first|100%\s+remote|remote|remoto)\b/i]&.squish
        end

        def location_signal(description)
          description.to_s[/\b(?:worldwide|global|latin america|latam|brazil|brasil|portugal|americas|europe)\b/i]&.squish
        end

        def external_job_id_for(url)
          URI.parse(url).path[%r{/jobs/(\d+)}, 1]
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
