module JobDiscovery
  module Adapters
    class LoxoJobBoardAdapter < Base
      HOST_SUFFIX = "app.loxo.co".freeze
      CLOSED_PATTERNS = /(job\s+closed|no\s+longer\s+accepting|position\s+filled|vaga\s+encerrada)/i

      def scan(source_scan:, window_days:)
        references = configured_references(source_scan) + board_references(source_scan) + discovered_references

        references.uniq { |reference| external_job_id_for(reference.fetch(:url)) || reference.fetch(:url) }.filter_map do |reference|
          next if outside_window?(reference[:published_at], window_days)
          next if reference[:title].present? && !policy.potential_match?(reference[:title])

          source_scan.record_page!
          build_candidate_from_page(source_scan:, reference:, window_days:)
        end
      end

      private
        def build_candidate_from_page(source_scan:, reference:, window_days:)
          page_url = reference.fetch(:url)
          document = html_document(page_url)
          title = meta_content(document, "og:title", property: true).presence || reference[:title]
          title = title.to_s.squish
          return unless title.present? && policy.potential_match?(title)

          description = extracted_description(document)
          canonical_url = normalized_job_url(meta_content(document, "og:url", property: true)) || normalized_job_url(page_url)
          apply_url = extracted_apply_url(document, canonical_url)
          published_at = reference[:published_at]
          return if outside_window?(published_at, window_days)

          decision = expired_result("vaga encerrada na pagina da Loxo") if inactive_page?(document, apply_url)

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "Loxo",
            source_kind: source_scan.job_source.source_kind.presence || "ats",
            source_slug: source_scan.job_source.slug.presence || "loxo",
            title:,
            company_name: company_name(document, source_scan),
            apply_url: apply_url.presence || canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text: reference[:remote_text].presence || labeled_value(document, "Location")&.match(/remot|worldwide/i)&.to_s,
            location_text: reference[:location_text].presence || labeled_value(document, "Location"),
            description:,
            posted_text: reference[:posted_text].presence || (published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica"),
            published_at:,
            external_job_id: external_job_id_for(canonical_url),
            payload: {
              board_url: reference[:board_url],
              listed_job_type: reference[:job_type],
              listed_date: reference[:posted_text],
              employment_type: labeled_value(document, "Employment Type"),
              compensation: labeled_value(document, "Compensation")
            },
            decision:
          )
        end

        def board_references(source_scan)
          board_urls(source_scan).flat_map do |board_url|
            source_scan.record_page!
            document = html_document(board_url)

            document.css(".jobs-listing-card").filter_map do |card|
              anchor = card.at_css("a.job-title[href]")
              next unless anchor

              url = normalized_job_url(absolute_url(board_url, anchor["href"]))
              next unless url

              posted_text = card.at_css(".job-date")&.text.to_s.squish
              location_text = normalized_card_location(card.at_css(".job-location")&.text)

              {
                url:,
                title: anchor.text.to_s.squish,
                published_at: parse_relative_time(posted_text),
                posted_text:,
                location_text:,
                remote_text: location_text.to_s.match?(/remote|remot[oa]/i) ? location_text : nil,
                job_type: card.at_css(".job-type")&.text.to_s.squish.presence,
                board_url:
              }
            end
          end
        end

        def configured_references(source_scan)
          Array(source_scan.job_source.settings["seed_urls"]).filter_map do |url|
            normalized = normalized_job_url(url)
            { url: normalized } if normalized
          end
        end

        def discovered_references
          known_hosted_urls(host_suffixes: [ HOST_SUFFIX ]).filter_map do |url|
            normalized = normalized_job_url(url)
            { url: normalized } if normalized
          end
        end

        def board_urls(source_scan)
          Array(source_scan.job_source.settings["board_urls"])
            .map { |url| canonical_url_string(url) }
            .reject(&:blank?)
            .uniq
        end

        def normalized_job_url(url)
          uri = URI.parse(url.to_s.strip)
          return unless uri.host.to_s.end_with?(".loxo.co")

          segments = uri.path.split("/").reject(&:blank?)
          return unless segments.length == 2 && segments.first == "job"

          "#{uri.scheme || 'https'}://#{uri.host}/job/#{CGI.unescape(segments.last)}"
        rescue URI::InvalidURIError
          nil
        end

        def extracted_description(document)
          payload = document.at_css("#public-job-description-json")&.text.to_s
          html = JSON.parse(payload).fetch("description", "") if payload.present?
          html = document.at_css(".cleanslate")&.inner_html if html.blank?

          Nokogiri::HTML.fragment(html.to_s).text.squish
        rescue JSON::ParserError
          document.at_css(".cleanslate")&.text.to_s.squish
        end

        def extracted_apply_url(document, page_url)
          href = document.at_css("a.job-apply-link[href]")&.[]("href")
          href.present? ? absolute_url(page_url, href) : nil
        rescue URI::InvalidURIError
          nil
        end

        def company_name(document, source_scan)
          document.at_css("title")&.text.to_s.split("|").second.to_s.squish.presence ||
            source_scan.job_source.name.presence ||
            "Empresa nao identificada"
        end

        def labeled_value(document, label)
          paragraph = document.css(".cleanslate p").find do |node|
            node.at_css("strong")&.text.to_s.delete_suffix(":").casecmp?(label)
          end
          return unless paragraph

          paragraph.text.sub(/\A#{Regexp.escape(label)}:\s*/i, "").squish.presence
        end

        def meta_content(document, key, property: false)
          attribute = property ? "property" : "name"
          document.at_css("meta[#{attribute}='#{key}']")&.[]("content").to_s.strip
        end

        def normalized_card_location(value)
          value.to_s.squish.sub(/\A(?:wifi|location_on)\s*/i, "").presence
        end

        def parse_relative_time(value)
          match = value.to_s.downcase.match(/(?:about\s+)?(\d+)\s+(hour|day|week|month|year)s?\s+ago/)
          return unless match

          amount = match[1].to_i
          duration = case match[2]
          when "hour" then amount.hours
          when "day" then amount.days
          when "week" then amount.weeks
          when "month" then (amount * 30).days
          when "year" then amount.years
          end
          Time.current - duration
        end

        def outside_window?(published_at, window_days)
          published_at.present? && published_at < window_days.days.ago.beginning_of_day
        end

        def inactive_page?(document, apply_url)
          apply_url.blank? || document.text.match?(CLOSED_PATTERNS)
        end

        def expired_result(reason)
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

        def external_job_id_for(url)
          URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s.presence
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
