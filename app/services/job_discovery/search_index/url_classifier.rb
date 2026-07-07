module JobDiscovery
  module SearchIndex
    class UrlClassifier
      Discovery = Struct.new(:source_slug, :setting_key, :setting_value, :url, keyword_init: true)

      def call(url)
        uri = URI.parse(url.to_s)
        host = normalized_host(uri.host)
        segments = uri.path.split("/").reject(&:blank?)

        case host
        when "jobs.ashbyhq.com"
          discovery("ashby", "board_slugs", segments.first, url)
        when "job-boards.greenhouse.io", "boards.greenhouse.io"
          discovery("greenhouse", "board_tokens", segments.first, url)
        when "jobs.lever.co"
          discovery("lever", "company_slugs", segments.first, url)
        when "jobs.smartrecruiters.com"
          discovery("smartrecruiters", "company_identifiers", segments.first, url)
        when "jobs.quickin.io"
          discovery("quickin", "company_slugs", segments.first, url)
        when "jobs.recrutei.com.br"
          discovery("recrutei", "company_labels", segments.first, url)
        end
      rescue URI::InvalidURIError
        nil
      end

      private
        def discovery(source_slug, setting_key, setting_value, url)
          value = setting_value.to_s.strip
          return if value.blank? || value.match?(/\A(?:jobs?|apply|job|careers?)\z/i)
          return unless value.match?(/\A[a-z0-9][a-z0-9_-]*\z/i)

          Discovery.new(source_slug:, setting_key:, setting_value: value, url:)
        end

        def normalized_host(host)
          host.to_s.downcase.sub(/\Awww\./, "")
        end
    end
  end
end
