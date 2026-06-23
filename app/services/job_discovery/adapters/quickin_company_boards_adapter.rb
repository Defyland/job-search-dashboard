require "cgi"
require "set"

module JobDiscovery
  module Adapters
    class QuickinCompanyBoardsAdapter < Base
      HOST = "jobs.quickin.io".freeze
      CLOSED_PATTERNS = /(vaga\s+encerrada|encerrad[ao]|expired|indispon[ií]vel|unavailable|not\s+found|job\s+closed|no\s+longer\s+accepting\s+applications)/i

      def scan(source_scan:, window_days:)
        company_slugs(source_scan).flat_map do |company_slug|
          scan_company_board(source_scan:, company_slug:, window_days:)
        end
      end

      private
        def scan_company_board(source_scan:, company_slug:, window_days:)
          candidates = []
          seen_urls = Set.new
          page_limit = [ source_scan.job_source.settings.fetch("max_pages", default_page_limit(window_days)).to_i, 1 ].max

          1.upto(page_limit) do |page_number|
            source_scan.record_page!
            page_url = board_page_url(company_slug, page_number)
            cards = extract_job_cards(html_document(page_url), page_url:, company_slug:)
            break if cards.empty?

            fresh_cards = cards.reject { |card| seen_urls.include?(card.fetch(:url)) }
            break if fresh_cards.empty?

            fresh_cards.each do |card|
              seen_urls << card.fetch(:url)
              next unless policy.potential_match?(card.fetch(:title))

              candidate = build_candidate_from_card(source_scan:, company_slug:, card:, window_days:)
              candidates << candidate if candidate
            end
          end

          candidates
        end

        def build_candidate_from_card(source_scan:, company_slug:, card:, window_days:)
          document = html_document(card.fetch(:url))
          posting = parse_job_posting_json(document)
          title = posting["title"].to_s.squish.presence || card.fetch(:title)
          return unless title.present?

          published_at = parse_time(posting["datePosted"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          canonical_url = canonical_url_string(card.fetch(:url))
          apply_url = extract_apply_url(document, canonical_url)
          valid_through = parse_time(posting["validThrough"])

          decision =
            if inactive_job_page?(document:, apply_url:, valid_through:)
              expired_result(reason: inactivity_reason(document:, apply_url:, valid_through:))
            end

          description = normalized_description(posting["description"])
          company_name = posting.dig("hiringOrganization", "name").presence ||
            company_name_for_url(canonical_url) ||
            company_slug.tr("-", " ").titleize

          build_candidate(
            source_scan:,
            source_name: "Quickin",
            source_kind: "ats",
            source_slug: "quickin",
            title:,
            company_name:,
            apply_url: apply_url.presence || canonical_url,
            canonical_url:,
            source_url: canonical_url,
            remote_text: card[:remote_text].presence || extracted_remote_text(document),
            location_text: card[:location_text].presence || extracted_location_text(posting),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: posting.dig("identifier", "value").presence || external_job_id_for(canonical_url),
            payload: {
              company_slug:,
              employment_type: posting["employmentType"],
              valid_through: posting["validThrough"],
              job_benefits: normalized_description(posting["jobBenefits"]),
              contract_name: extracted_contract_name(document),
              listed_location: card[:location_text],
              listed_workplace_type: card[:remote_text]
            },
            decision:
          )
        end

        def company_slugs(source_scan)
          configured = Array(source_scan.job_source.settings["company_slugs"])
          discovered = known_hosted_urls(host_suffixes: [ HOST ]).filter_map do |url|
            extract_company_slug(url)
          end

          (configured + discovered).map { |slug| slug.to_s.strip }.reject(&:blank?).uniq
        end

        def board_page_url(company_slug, page_number)
          base_url = "https://#{HOST}/#{company_slug}/jobs"
          page_number == 1 ? base_url : "#{base_url}?page=#{page_number}"
        end

        def extract_job_cards(document, page_url:, company_slug:)
          document.css("table tbody tr").filter_map do |row|
            anchor = row.at_css("th a[href]")
            next unless anchor

            url = canonical_url_string(absolute_url(page_url, anchor["href"]))
            next unless job_url?(url, company_slug)

            title = anchor.text.to_s.squish
            next if title.blank?

            metadata = row.css("td span").map { |node| node.text.to_s.squish }.reject(&:blank?)

            {
              title:,
              url:,
              location_text: metadata.first,
              remote_text: metadata.second
            }
          end.uniq { |card| card[:url] }
        end

        def job_url?(url, company_slug)
          uri = URI.parse(url)
          return false unless normalized_host(url) == HOST

          path_segments = uri.path.split("/").reject(&:blank?)
          path_segments.length == 3 &&
            path_segments.first == company_slug &&
            path_segments.second == "jobs" &&
            path_segments.third.present?
        rescue URI::InvalidURIError
          false
        end

        def extract_company_slug(url)
          uri = URI.parse(url)
          return unless normalized_host(url) == HOST

          path_segments = uri.path.split("/").reject(&:blank?)
          return if path_segments.empty?

          path_segments.first
        rescue URI::InvalidURIError
          nil
        end

        def extract_apply_url(document, page_url)
          href = document.at_css("a[href*='/apply?job_id=']")&.[]("href").to_s.strip
          return if href.blank?

          canonical_url_string(absolute_url(page_url, href))
        end

        def extracted_remote_text(document)
          document.at_css("h5 .badge")&.text.to_s.squish.presence
        end

        def extracted_location_text(posting)
          address = posting.dig("jobLocation", "address").to_h
          [
            address["addressLocality"],
            address["addressRegion"],
            address["addressCountry"]
          ].map { |value| value.to_s.squish }.reject(&:blank?).join(", ").presence
        end

        def extracted_contract_name(document)
          header = document.at_css("section h5")&.text.to_s
          header.split(",").first.to_s.squish.presence
        end

        def inactive_job_page?(document:, apply_url:, valid_through:)
          valid_through.present? && valid_through < Time.current ||
            document.text.to_s.match?(CLOSED_PATTERNS) ||
            apply_url.blank?
        end

        def inactivity_reason(document:, apply_url:, valid_through:)
          return "vaga encerrada na pagina do Quickin" if document.text.to_s.match?(CLOSED_PATTERNS)
          return "vaga fora da janela de candidatura do Quickin" if valid_through.present? && valid_through < Time.current
          return "vaga sem link de candidatura ativo na pagina do Quickin" if apply_url.blank?

          "vaga indisponivel no Quickin"
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
          URI.parse(url.to_s).path.split("/").reject(&:blank?).last.to_s.presence
        rescue URI::InvalidURIError
          nil
        end

        def normalized_description(value)
          Nokogiri::HTML.fragment(CGI.unescapeHTML(value.to_s)).text.squish
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def default_page_limit(window_days)
          window_days >= 20 ? 6 : 3
        end
    end
  end
end
