require "cgi"
require "json"

module JobDiscovery
  module Adapters
    class RecruteiCompanyBoardsAdapter < Base
      HOST = "jobs.recrutei.com.br".freeze
      APPLY_HOST = "talent.recrutei.com.br".freeze

      def scan(source_scan:, window_days:)
        vacancy_urls = seeded_vacancy_urls(source_scan)

        company_labels(source_scan).each do |company_label|
          source_scan.record_page!
          vacancy_urls.concat(vacancy_urls_from_board(company_label))
        end

        vacancy_urls.uniq.filter_map do |vacancy_url|
          build_candidate_from_vacancy(source_scan:, vacancy_url:, window_days:)
        end
      end

      private
        def build_candidate_from_vacancy(source_scan:, vacancy_url:, window_days:)
          document = html_document(vacancy_url)
          next_data = parse_next_data(document)
          vacancy = next_data.dig("props", "pageProps", "retorno", "vacancy").to_h
          return if vacancy["expired"] == true

          posting = parse_job_posting_json(document)
          title = vacancy["title"].presence || posting["title"].to_s.squish
          return unless policy.potential_match?(title)

          published_at = parse_published_at(vacancy["published_at"]) || parse_time(vacancy["created_at"]) || parse_published_at(posting["datePosted"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          company = next_data.dig("props", "pageProps", "retorno", "company", "company").to_h
          company_label = company["label"].presence || extract_company_label(vacancy_url)
          canonical_url = canonical_url_string(vacancy["public_link"].presence || document.at_css("link[rel='canonical']")&.[]("href") || vacancy_url)
          description = normalized_description(vacancy["description"].presence || posting["description"])
          apply_url = extract_apply_url_from_detail(document, company_label, vacancy["id"])

          build_candidate(
            source_scan:,
            source_name: "Recrutei",
            source_kind: "ats",
            source_slug: "recrutei",
            title:,
            company_name: company["name"].presence || posting.dig("hiringOrganization", "name").presence || company_name_for_url(canonical_url) || company_label.to_s.tr("-", " ").titleize,
            apply_url:,
            canonical_url:,
            source_url: canonical_url,
            remote_text: remote_signal(vacancy),
            location_text: location_signal(vacancy),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: vacancy["id"].to_s.presence || canonical_url[%r{/vacancy/(\d+)}, 1].to_s,
            payload: {
              company_label:,
              regime: vacancy.dig("regime", "description"),
              remote_code: vacancy["remote"],
              expired_at: vacancy["expired_at"],
              inclusive: vacancy["is_inclusive"],
              public_link: vacancy["public_link"]
            }
          )
        rescue JSON::ParserError
          nil
        end

        def company_labels(source_scan)
          configured = Array(source_scan.job_source.settings["company_labels"])
          discovered = known_hosted_urls(host_suffixes: [ HOST ]).filter_map do |url|
            extract_company_label(url)
          end

          (configured + discovered).map { |label| label.to_s.strip }.reject(&:blank?).uniq
        end

        def seeded_vacancy_urls(source_scan)
          configured = Array(source_scan.job_source.settings["vacancy_urls"])
          discovered = known_hosted_urls(host_suffixes: [ HOST ]).select do |url|
            url.include?("/vacancy/")
          end

          (configured + discovered).map { |url| canonical_url_string(url) }.reject(&:blank?).uniq
        end

        def vacancy_urls_from_board(company_label)
          board_url = "https://#{HOST}/#{company_label}/vacancies"
          html = fetcher.call(board_url)

          html.scan(%r{/#{Regexp.escape(company_label)}/vacancy/[a-z0-9-]+}i)
              .map { |path| absolute_url(board_url, path) }
        end

        def extract_company_label(url)
          uri = URI.parse(url)
          return unless normalized_host(url) == HOST

          uri.path.split("/").reject(&:blank?).first
        rescue URI::InvalidURIError
          nil
        end

        def parse_next_data(document)
          script = document.at_css("script#__NEXT_DATA__")
          return {} unless script

          JSON.parse(CGI.unescapeHTML(script.text))
        rescue JSON::ParserError
          {}
        end

        def extract_apply_url_from_detail(document, company_label, vacancy_id)
          apply_link = document.css("a[href]").find do |node|
            href = node["href"].to_s
            href.include?(APPLY_HOST) && node.text.to_s.match?(/candidat|inscrev|apply/i)
          end

          return canonical_url_string(apply_link["href"]) if apply_link
          return if company_label.blank? || vacancy_id.blank?

          "https://#{APPLY_HOST}/#{company_label}/#{vacancy_id}/signup"
        end

        def remote_signal(vacancy)
          case vacancy["remote"]
          when 1
            "Remoto"
          when 2
            [ location_signal(vacancy), "Remoto" ].compact_blank.join(" ou ")
          when 3
            [ location_signal(vacancy), "Híbrido" ].compact_blank.join(" e ")
          else
            location_signal(vacancy)
          end
        end

        def location_signal(vacancy)
          vacancy["location"].presence || [ vacancy["city"], vacancy["state"], vacancy["country"] ].compact_blank.join(", ")
        end

        def normalized_description(value)
          Nokogiri::HTML.fragment(CGI.unescapeHTML(value.to_s)).text.squish
        end

        def parse_published_at(value)
          return if value.blank?

          Time.zone.strptime(value.to_s, "%d/%m/%Y %H:%M:%S")
        rescue ArgumentError
          parse_time(value)
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
