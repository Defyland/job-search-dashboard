require "json"

module JobDiscovery
  module Adapters
    # Reads vacancies published as public Notion pages.
    #
    # Notion serves those URLs as an empty JavaScript shell, so the HTML is
    # useless. The content comes from the same public loadPageChunk endpoint the
    # browser calls, which needs no authentication for a page shared publicly.
    #
    # Notion exposes no way to enumerate a workspace's public pages: its search
    # endpoint returns nothing without membership and parent blocks are normally
    # private. This adapter is therefore seeded with explicit page URLs.
    class NotionPublicPagesAdapter < Base
      CHUNK_ENDPOINT = "https://www.notion.so/api/v3/loadPageChunk".freeze
      CHUNK_LIMIT = 100

      def scan(source_scan:, window_days:)
        page_entries(source_scan).filter_map do |entry|
          source_scan.record_page!
          build_candidate_from_page(source_scan:, entry:, window_days:)
        end.uniq { |candidate| candidate.fetch(:canonical_url) }
      end

      private
        def build_candidate_from_page(source_scan:, entry:, window_days:)
          page_url = entry.fetch(:url)
          page_id = page_id_from(page_url)
          return unless page_id

          blocks = load_blocks(page_id)
          root = blocks.find { |block| block["id"] == page_id } || blocks.find { |block| block["type"] == "page" }
          return unless root

          title = block_text(root)
          return unless title.present? && policy.potential_match?(title)

          published_at = notion_time(root["created_time"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          description = description_from(blocks, root)
          notion_url = canonical_url_string(page_url)
          # When the same vacancy is also published on the company's own site,
          # the site URL stays the canonical identity so the two sources dedupe
          # into a single job instead of showing up twice.
          canonical_url = canonical_url_string(entry[:mirror_of]).presence || notion_url

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "Notion",
            source_kind: source_scan.job_source.source_kind.presence || "company",
            source_slug: source_scan.job_source.slug.presence || "notion",
            title:,
            company_name: company_name(source_scan),
            apply_url: notion_url,
            canonical_url:,
            source_url: notion_url,
            remote_text: remote_signal(description),
            location_text: location_signal(description),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            # A mirrored page must also share the origin's external id, because
            # the fingerprint is built from company, title, host and this id.
            external_job_id: external_job_id_for(canonical_url, page_id),
            payload: {
              notion_page_id: page_id,
              notion_url:,
              mirror_of: entry[:mirror_of],
              last_edited_at: notion_time(root["last_edited_time"]),
              block_count: blocks.size,
              apply_flow: "notion_page"
            }
          )
        rescue JSON::ParserError
          nil
        end

        def load_blocks(page_id)
          request = {
            pageId: page_id,
            limit: CHUNK_LIMIT,
            cursor: { stack: [] },
            chunkNumber: 0,
            verticalColumns: false
          }
          payload = JSON.parse(fetcher.post(CHUNK_ENDPOINT, body: request.to_json))

          Array(payload.dig("recordMap", "block")&.values).filter_map do |node|
            node.dig("value", "value") || node["value"]
          end
        end

        # Accepts either a plain URL string or a hash with an optional
        # `mirror_of` pointing at the same vacancy on the company's own site.
        def page_entries(source_scan)
          Array(source_scan.job_source.settings["page_urls"]).filter_map do |entry|
            if entry.is_a?(Hash)
              url = entry["url"].to_s.strip
              { url:, mirror_of: entry["mirror_of"].to_s.strip.presence } if url.present?
            else
              url = entry.to_s.strip
              { url:, mirror_of: nil } if url.present?
            end
          end.uniq { |entry| entry.fetch(:url) }
        end

        def company_name(source_scan)
          source_scan.job_source.settings["company_name"].presence ||
            source_scan.job_source.name.presence ||
            "Empresa nao identificada"
        end

        # Notion page URLs end in a 32-character hex id, dashed or not.
        def page_id_from(url)
          raw = URI.parse(url.to_s.strip).path.to_s.split("/").last.to_s
          hex = raw.tr("-", "")[-32, 32]
          return unless hex&.match?(/\A[0-9a-f]{32}\z/i)

          [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
        rescue URI::InvalidURIError
          nil
        end

        def description_from(blocks, root)
          blocks.reject { |block| block["id"] == root["id"] }
                .map { |block| block_text(block) }
                .compact_blank
                .join(" ")
                .squish
        end

       def block_text(block)
         Array(block.dig("properties", "title")).map { |segment| segment[0].to_s }.join.squish
       end

        def external_job_id_for(canonical_url, page_id)
          return page_id if canonical_url.to_s.include?("notion.site")

          URI.parse(canonical_url.to_s).path.split("/").reject(&:blank?).last.to_s.presence || page_id
        rescue URI::InvalidURIError
          page_id
        end

        def remote_signal(description)
          description.to_s[/\b(?:fully\s+remote|remote[-\s]?first|100%\s+remote|remote|remoto)\b/i]&.squish
        end

        def location_signal(description)
          description.to_s[/\b(?:worldwide|global|latin america|latam|brazil|brasil|portugal|europe|americas|anywhere)\b/i]&.squish
        end

        def notion_time(value)
          return if value.blank?

          Time.zone.at(Integer(value) / 1000)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
