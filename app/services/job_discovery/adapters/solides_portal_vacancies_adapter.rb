require "cgi"
require "json"
require "set"

module JobDiscovery
  module Adapters
    class SolidesPortalVacanciesAdapter < Base
      API_URL = "https://apigw.solides.com.br/jobs/v3/portal-vacancies-new/".freeze
      BASE_URL = "https://vagas.solides.com.br".freeze
      DEFAULT_SEARCH_QUERIES = [
        "react",
        "react native",
        "ruby",
        "rails"
      ].freeze

      def scan(source_scan:, window_days:)
        cutoff = window_days.days.ago.beginning_of_day
        page_limit = [ source_scan.job_source.settings.fetch("max_pages", default_page_limit(window_days)).to_i, 1 ].max
        queries = configured_queries(source_scan)
        seen_ids = Set.new
        candidates = []

        queries.each do |query|
          page = 1
          total_pages = nil

          while page <= page_limit && (total_pages.nil? || page <= total_pages)
            source_scan.record_page!
            response = fetch_page(query:, page:)
            total_pages = response["totalPages"].to_i if response["totalPages"].present?
            jobs = Array(response["data"])
            break if jobs.empty?

            jobs.each do |job|
              next unless seen_ids.add?(job["id"].to_s)

              candidate = build_candidate_from_job(source_scan:, job:, cutoff:)
              candidates << candidate if candidate
            end

            break if stale_page?(jobs, cutoff)

            page += 1
          end
        end

        candidates
      end

      private
        def fetch_page(query:, page:)
          url = "#{API_URL}?#{URI.encode_www_form(title: query, page: page)}"
          JSON.parse(fetcher.call(url)).fetch("data", {})
        end

        def build_candidate_from_job(source_scan:, job:, cutoff:)
          title = job["title"].to_s.squish
          return if title.blank?
          return unless policy.potential_match?(title)

          published_at = parse_date(job["createdAt"]) || parse_time(job["date"])
          return if published_at.present? && published_at < cutoff

          detail = fetch_detail(job)
          return unless active_vacancy?(detail)

          description = detail_description(detail, job)
          apply_url = canonical_url_string(detail["redirectLink"].presence || job["redirectLink"])
          return if apply_url.blank?

          detail_url = detail_url_for(job["id"], title)

          build_candidate(
            source_scan:,
            source_name: "Sólides",
            source_kind: "ats",
            source_slug: "solides",
            title: detail["title"].presence || title,
            company_name: detail["companyName"].presence || job["companyName"].presence || company_name_for_url(apply_url) || "Sólides",
            apply_url:,
            canonical_url: detail_url,
            source_url: detail_url,
            remote_text: remote_signal(detail, job),
            location_text: location_signal(detail, job),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id: job["id"].to_s,
            payload: {
              redirect_link: detail["redirectLink"].presence || job["redirectLink"],
              current_state: detail["currentState"],
              receiving_resume: detail["receivingResume"],
              people_with_disabilities: detail["peopleWithDisabilities"],
              pcd_only: detail["pcdOnly"],
              job_type: detail["jobType"].presence || job["jobType"],
              affirmative: Array(detail["affirmative"]).map { |item| item["name"] },
              contract_types: Array(detail["recruitmentContractType"]).map { |item| item["name"] }
            }
          )
        end

        def fetch_detail(job)
          document = html_document(detail_url_for(job["id"], job["title"]))
          next_data = parse_next_data(document)
          next_data.dig("props", "pageProps", "vacancy").to_h
        end

        def parse_next_data(document)
          script = document.at_css("script#__NEXT_DATA__")
          return {} unless script

          JSON.parse(CGI.unescapeHTML(script.text))
        rescue JSON::ParserError
          {}
        end

        def active_vacancy?(detail)
          return false if detail.blank?
          return false if detail["receivingResume"] == false
          return false if detail["companyActivated"] == false
          return false if detail["jobsActivated"] == false
          return false if detail["paymentUpToDate"] == false

          detail["currentState"].blank? || detail["currentState"] == "em_andamento"
        end

        def detail_description(detail, job)
          [
            normalized_description(detail["description"].presence || job["description"]),
            Array(detail["affirmative"]).map { |item| item["name"] },
            Array(detail["seniority"]).map { |item| item["name"] },
            Array(detail["recruitmentContractType"]).map { |item| item["name"] }
          ].flatten.compact.join(" | ")
        end

        def remote_signal(detail, job)
          job_type = detail["jobType"].presence || job["jobType"]

          case job_type.to_s.downcase
          when "remoto"
            "Remoto"
          when "hibrido"
            "Híbrido"
          when "presencial"
            "Presencial"
          else
            job_type.to_s.humanize.presence || location_signal(detail, job)
          end
        end

        def location_signal(detail, job)
          address = detail["address"].to_h
          city = extract_location_name(detail["city"]) || extract_location_name(address["city"]) || extract_location_name(job["city"])
          state = extract_location_name(detail["state"]) || extract_location_name(address["state"]) || extract_location_name(job["state"])
          country = extract_location_name(address["country"]) || extract_location_name(job["country"])

          [ city, state, country ].compact_blank.join(", ")
        end

        def detail_url_for(job_id, title)
          "#{BASE_URL}/vaga/#{job_id}/#{title.to_s.parameterize}"
        end

        def configured_queries(source_scan)
          queries = Array(source_scan.job_source.settings["search_queries"]).map { |value| value.to_s.squish }.reject(&:blank?)
          queries.presence || DEFAULT_SEARCH_QUERIES
        end

        def stale_page?(jobs, cutoff)
          dated_jobs = Array(jobs).filter_map do |job|
            parse_date(job["createdAt"]) || parse_time(job["date"])
          end
          return false if dated_jobs.empty?

          dated_jobs.all? { |published_at| published_at < cutoff }
        end

        def parse_date(value)
          return if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def parse_time(value)
          return if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def extract_location_name(value)
          case value
          when Hash
            value["name"].presence
          else
            value.to_s.presence
          end
        end

        def normalized_description(value)
          Nokogiri::HTML.fragment(CGI.unescapeHTML(value.to_s)).text.squish
        end

        def default_page_limit(window_days)
          window_days >= 20 ? 8 : 3
        end
    end
  end
end
