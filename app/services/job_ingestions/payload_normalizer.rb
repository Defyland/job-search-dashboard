module JobIngestions
  class PayloadNormalizer
    TRACKING_QUERY_KEYS = %w[fbclid gclid jobBoardSource utm_campaign utm_content utm_medium utm_source].freeze

    def normalize(item)
      item = item.deep_stringify_keys
      apply_url = canonicalize_url(item["apply_url"].presence || item["direct_application_link"].presence || item["link"])
      source_url = canonicalize_url(item["source_url"].presence || item["job_url"].presence || item["source_page"])
      canonical_url = canonicalize_url(item["canonical_url"].presence || source_url || apply_url)
      published_at = parse_time(item["published_at"]) || parse_time(item["last_updated_at"])

      {
        title: item["title"].presence || item["job_title"].to_s.squish,
        company_name: item["company"].presence || item["company_name"].to_s.squish,
        apply_url: apply_url,
        canonical_url: canonical_url,
        source_url: source_url || canonical_url,
        ats_name: item["source_name"].presence || item["source"].presence,
        external_job_id: item["external_job_id"].presence || item["job_id"].presence,
        remote_text: item["remote_signal"].presence || item["remote"].presence || item["location"].presence,
        location_text: item["location"].presence || item["location_text"].presence,
        seniority: item["seniority"].presence || "senior",
        match_strength: normalize_match_strength(item["match_strength"]),
        reason: item["reason"].presence || item["match_reason"].presence || "match validado pela automacao",
        score: normalize_score(item, published_at:),
        posted_text: item["recency_text"].presence || item["posted_text"].presence,
        published_at:,
        fingerprint: normalize_fingerprint(item, canonical_url, apply_url),
        stack_tags: normalize_stack_tags(item),
        source_host: normalize_host(canonical_url || apply_url),
        user_state: :new_match
      }
    end

    def expired?(item)
      item = item.deep_stringify_keys
      status = item["status"].to_s.downcase
      return true if item["active"] == false

      %w[closed expired unavailable inactive].include?(status)
    end

    private
      def normalize_stack_tags(item)
        Array(item["stack_tags"].presence || item["stack_match"].presence || item["stack"]).flat_map { |value| value.to_s.split(",") }
                                                                                               .map { |value| value.downcase.squish }
                                                                                               .reject(&:blank?)
                                                                                               .uniq
      end

      def normalize_fingerprint(item, canonical_url, apply_url)
        explicit_fingerprint = item["fingerprint"].to_s.strip
        return explicit_fingerprint if explicit_fingerprint.present?

        [
          item["company"].presence || item["company_name"],
          item["title"].presence || item["job_title"],
          normalize_host(canonical_url || apply_url),
          item["external_job_id"].presence || item["job_id"]
        ].map { |value| value.to_s.downcase.squish }
         .reject(&:blank?)
         .join("::")
      end

      def normalize_match_strength(value)
        JobMatch.match_strengths.fetch(value.to_s, JobMatch.match_strengths.fetch("strong"))
      end

      def normalize_score(item, published_at:)
        return item["score"].to_i if item["score"].present?

        base_score = normalize_match_strength(item["match_strength"]) == JobMatch.match_strengths.fetch("strong") ? 90 : 70
        base_score += 5 if published_at.present? && published_at >= 24.hours.ago
        base_score
      end

      def canonicalize_url(url)
        return if url.blank?

        uri = URI.parse(url.to_s.strip)
        uri.fragment = nil

        if uri.query.present?
          filtered_query = URI.decode_www_form(uri.query).reject { |(key, _)| TRACKING_QUERY_KEYS.include?(key) }
          uri.query = filtered_query.any? ? URI.encode_www_form(filtered_query) : nil
        end

        uri.to_s.delete_suffix("/")
      rescue URI::InvalidURIError
        url.to_s.strip.delete_suffix("/")
      end

      def normalize_host(url)
        URI.parse(url).host.to_s.downcase.sub(/\Awww\./, "")
      rescue URI::InvalidURIError, NoMethodError
        ""
      end

      def parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
  end
end
