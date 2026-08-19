module JobDiscovery
  module Adapters
    class LufloxPositionsAdapter < Base
      API_URL = "https://firestore.googleapis.com/v1/projects/luflox-management-prod/databases/(default)/documents/positions".freeze
      CAREER_URL = "https://www.luflox.com/career/details".freeze

      def scan(source_scan:, window_days:)
        active_positions(source_scan).filter_map do |position|
          build_candidate_from_position(source_scan:, position:, window_days:)
        end
      end

      private
        def active_positions(source_scan)
          positions = []
          next_page_token = nil
          max_pages = [ source_scan.job_source.settings.fetch("max_pages", 5).to_i, 1 ].max

          max_pages.times do
            source_scan.record_page!
            response = JSON.parse(fetcher.call(api_url(next_page_token)))
            positions.concat(Array(response["documents"]).map { |document| decoded_document(document) })
            next_page_token = response["nextPageToken"].presence
            break unless next_page_token
          end

          positions.select { |position| position["status"] == "ACTIVE" }
        end

        def build_candidate_from_position(source_scan:, position:, window_days:)
          title = position["role"].to_s.squish
          return unless title.present? && policy.potential_match?(title)

          published_at = parse_time(position.dig("creation", "date") || position["createTime"])
          return if published_at.present? && published_at < window_days.days.ago.beginning_of_day

          external_job_id = position["id"].presence || position["documentId"]
          return if external_job_id.blank?

          canonical_url = "#{CAREER_URL}/#{external_job_id}"
          description = full_description(position)

          build_candidate(
            source_scan:,
            source_name: source_scan.job_source.name.presence || "Luflox",
            source_kind: source_scan.job_source.source_kind.presence || "company",
            source_slug: source_scan.job_source.slug.presence || "luflox",
            title:,
            company_name: "Luflox client",
            apply_url: "#{canonical_url}/apply?status=ACTIVE",
            canonical_url:,
            source_url: canonical_url,
            remote_text: position["modality"].to_s.squish.presence,
            location_text: location_signal(position, description),
            description:,
            posted_text: published_at ? "publicada em #{I18n.l(published_at.to_date)}" : "sem data publica",
            published_at:,
            external_job_id:,
            payload: {
              status: position["status"],
              type: position["type"],
              modality: position["modality"],
              seniority: position["seniority"],
              stack: position["stack"],
              salary: position["salary"],
              currency: position["currency"],
              payment_frequency: position["paymentFrequency"],
              years_of_experience: position["yoe"]
            }
          )
        end

        def api_url(page_token)
          url = "#{API_URL}?pageSize=100"
          page_token.present? ? "#{url}&pageToken=#{CGI.escape(page_token)}" : url
        end

        def decoded_document(document)
          decode_map(document.fetch("fields", {})).merge(
            "documentId" => document.fetch("name", "").split("/").last,
            "createTime" => document["createTime"],
            "updateTime" => document["updateTime"]
          )
        end

        def decode_map(fields)
          fields.to_h.transform_values { |value| decode_value(value) }
        end

        def decode_value(value)
          return value["stringValue"] if value.key?("stringValue")
          return value["integerValue"].to_i if value.key?("integerValue")
          return value["doubleValue"].to_f if value.key?("doubleValue")
          return value["booleanValue"] if value.key?("booleanValue")
          return value["timestampValue"] if value.key?("timestampValue")
          return nil if value.key?("nullValue")
          return Array(value.dig("arrayValue", "values")).map { |entry| decode_value(entry) } if value.key?("arrayValue")
          return decode_map(value.dig("mapValue", "fields")) if value.key?("mapValue")

          nil
        end

        def full_description(position)
          [
            position["description"],
            *Array(position["responsibilities"]),
            *Array(position["requirements"]),
            *Array(position["preferred"])
          ].compact_blank.join(" ").squish
        end

        def location_signal(position, description)
          explicit = [ position["location"], position["country"] ].compact_blank.join(", ").presence
          explicit || description.to_s[/\b(?:LATAM|Latin America|Brazil|Brasil|Portugal|Worldwide|Global)\b/i]&.squish
        end

        def parse_time(value)
          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end
    end
  end
end
