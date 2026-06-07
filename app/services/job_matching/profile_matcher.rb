module JobMatching
  class ProfileMatcher
    def initialize(profiles: SearchProfile.active.ordered)
      @profiles = Array(profiles)
    end

    def match(attributes:, payload:, source:)
      decisions(attributes:, payload:, source:).select(&:accepted?)
    end

    def decisions(attributes:, payload:, source:)
      @profiles.map do |profile|
        decision = JobDiscovery::Policy.new(search_profile: profile).classify(
          title: attributes[:title],
          remote_text: attributes[:remote_text],
          location_text: attributes[:location_text],
          description: policy_description(payload, attributes),
          source_slug: source.slug,
          posted_text: attributes[:posted_text],
          published_at: attributes[:published_at]
        )
      end
    end

    private
      def policy_description(payload, attributes)
        item = payload.deep_stringify_keys

        [
          item["description"],
          item["body"],
          item["requirements"],
          item["summary"],
          restrictive_payload_reason(item, attributes)
        ].flatten.compact.join(" ")
      end

      def restrictive_payload_reason(item, attributes)
        text = [ item["reason"], item["match_reason"], attributes[:reason] ].compact.join(" ")
        return if text.blank?

        text if text.match?(/\b(mulher(?:es)?|women|female|closed|expired|unavailable|expirad[ao]|encerrad[ao]|indispon[ií]vel|presencial|h[ií]brido|hybrid|on[-\s]?site)\b/i)
      end
  end
end
