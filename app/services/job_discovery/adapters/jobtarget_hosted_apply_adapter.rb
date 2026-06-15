module JobDiscovery
  module Adapters
    class JobtargetHostedApplyAdapter < Base
      HOST = "hosted-apply.jobtarget.com".freeze
      HOST_ALIASES = [ HOST, "hostedapply.jobtarget.com" ].freeze
      CLOSED_PATTERNS = /(no\s+longer\s+accepting\s+applications|application\s+closed|job\s+closed)/i

      def scan(source_scan:, window_days:)
        candidate_urls(source_scan).filter_map do |page_url|
          source_scan.record_page!
          build_candidate_from_page(source_scan:, page_url:, window_days:)
        end
      end

      private
        def build_candidate_from_page(source_scan:, page_url:, window_days:)
          document = html_document(page_url)
          canonical_url = extracted_canonical_url(document, page_url)
          title = document.at_css("h1")&.text.to_s.squish.presence || title_from_meta(document)
          return unless title.present?
          return unless policy.potential_match?(title)

          company_name = extracted_company_name(document) || company_name_from_meta_title(document) || company_name_for_url(canonical_url)
          location_text = extracted_location_text(document) || location_from_meta_title(document)
          description = extracted_description(document)
          remote_text = extracted_remote_text(title:, location_text:, description:)
          published_at = nil
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          decision =
            if closed_page?(document)
              expired_result(reason: "vaga encerrada na pagina do JobTarget")
            end

          build_candidate(
            source_scan:,
            source_name: "JobTarget Hosted Apply",
            source_kind: "ats",
            source_slug: "jobtarget-hosted-apply",
            title:,
            company_name: company_name.presence || "Empresa nao identificada",
            apply_url: canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text:,
            location_text:,
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: external_job_id_for(canonical_url),
            payload: {
              meta_title: meta_content(document, "title"),
              meta_description: meta_content(document, "description"),
              og_title: meta_content(document, "og:title", property: true),
              og_url: meta_content(document, "og:url", property: true)
            },
            decision:
          )
        end

        def candidate_urls(source_scan)
          configured = Array(source_scan.job_source.settings["seed_urls"])
          discovered = known_hosted_urls(host_suffixes: HOST_ALIASES)

          (configured + discovered).map { |url| normalized_job_url(url) }.reject(&:blank?).uniq
        end

        def normalized_job_url(url)
          uri = URI.parse(url.to_s.strip)
          return if uri.host.blank?

          "#{uri.scheme || 'https'}://#{uri.host}#{uri.path}".delete_suffix("/")
        rescue URI::InvalidURIError
          nil
        end

        def extracted_canonical_url(document, page_url)
          meta_content(document, "og:url", property: true).presence ||
            document.at_css("link[rel='canonical']")&.[]("href").to_s.strip.presence ||
            normalized_job_url(page_url)
        end

        def extracted_company_name(document)
          document.at_css(".item[title='Company']")&.text.to_s.squish.presence
        end

        def extracted_location_text(document)
          document.at_css(".item[title='Location']")&.text.to_s.squish.presence
        end

        def extracted_description(document)
          document.at_css("div.col_three_fifth")&.text.to_s.squish
        end

        def extracted_remote_text(title:, location_text:, description:)
          title.to_s[/\b(?:[[:alpha:]-]+\s+){0,2}remote\b/i]&.squish ||
            location_text.to_s[/\b(?:remot[oa]?|remote)\b/i]&.squish ||
            description.to_s[/\bremote from latin america\b/i]&.squish ||
            description.to_s[/\bfull[-\s]?time remote\b/i]&.squish
        end

        def title_from_meta(document)
          meta_title = meta_content(document, "og:title", property: true).presence || document.at_css("title")&.text.to_s
          meta_title.to_s.sub(/\s+in\s+.+\z/i, "").sub(/\s+-\s+.+\z/, "").squish.presence
        end

        def location_from_meta_title(document)
          meta_title = meta_content(document, "og:title", property: true).presence || document.at_css("title")&.text.to_s
          meta_title[/\s+in\s+(.+?)\s*(?:-\s+.+)?\z/i, 1]&.squish
        end

        def company_name_from_meta_title(document)
          document.at_css("title")&.text.to_s[/\s+-\s+(.+?)\s+-\s+Hosted Apply/i, 1]&.squish
        end

        def meta_content(document, key, property: false)
          attribute = property ? "property" : "name"
          document.at_css("meta[#{attribute}='#{key}']")&.[]("content").to_s.strip
        end

        def closed_page?(document)
          document.text.match?(CLOSED_PATTERNS)
        end

        def expired_result(reason:)
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
          basename = URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s
          basename[/([A-Za-z0-9]{8,})\z/, 1].presence || basename.presence
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
