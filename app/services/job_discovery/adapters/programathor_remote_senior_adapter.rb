module JobDiscovery
  module Adapters
    class ProgramathorRemoteSeniorAdapter < Base
      BASE_URL = "https://programathor.com.br/jobs-city/remoto?expertise=S%C3%AAnior".freeze

      def scan(source_scan:, window_days:)
        page_limit = [ source_scan.job_source.settings.fetch("max_pages", default_page_limit(window_days)).to_i, 1 ].max
        candidates = []

        (1..page_limit).each do |page|
          page_url = page == 1 ? BASE_URL : "#{BASE_URL}&page=#{page}"
          source_scan.record_page!
          candidates.concat(scan_page(source_scan:, page_url:, page:))
        end

        candidates
      end

      private
        def scan_page(source_scan:, page_url:, page:)
          document = html_document(page_url)
          document.css("a[href^='/jobs/']").filter_map do |anchor|
            raw_title = anchor.text.to_s.squish
            next unless raw_title.present?
            next unless policy.potential_match?(raw_title)

            job_url = absolute_url(page_url, anchor["href"])
            detail = html_document(job_url)
            title = extract_title(detail, raw_title)
            company_name = extract_company_name(detail, raw_title)
            page_text = detail.text.to_s.squish

            build_candidate(
              source_scan:,
              source_name: "ProgramaThor",
              source_kind: "platform",
              source_slug: "programathor",
              title:,
              company_name:,
              apply_url: job_url,
              canonical_url: job_url,
              source_url: job_url,
              remote_text: "Remoto",
              location_text: "Remoto",
              description: page_text,
              posted_text: "sem data publica; pagina #{page} do board",
              published_at: nil,
              external_job_id: job_url[%r{/jobs/(\d+)}, 1],
              payload: {
                page:,
                page_url:,
                raw_title:
              }
            )
          end
        end

        def extract_title(document, fallback)
          document.at_css("title")&.text.to_s.split("-").first.to_s.squish.presence || fallback
        end

        def extract_company_name(document, fallback)
          text = document.text.to_s
          text[/Empresa\s+([^\n]+)/i, 1].to_s.squish.presence || fallback.split(/Remoto/i).last.to_s.squish.presence || "ProgramaThor"
        end

        def default_page_limit(window_days)
          window_days >= 20 ? 12 : 4
        end
    end
  end
end
