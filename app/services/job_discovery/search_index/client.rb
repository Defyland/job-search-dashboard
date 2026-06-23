require "json"

module JobDiscovery
  module SearchIndex
    class Client
      DEFAULT_ENDPOINT = "https://serpapi.com/search.json".freeze

      Result = Struct.new(:url, :title, :snippet, keyword_init: true)

      def self.configured?
        api_key.present?
      end

      def self.api_key
        ENV["SEARCH_INDEX_API_KEY"].presence || ENV["SERPAPI_API_KEY"]
      end

      def initialize(
        provider: ENV.fetch("SEARCH_INDEX_PROVIDER", "serpapi"),
        endpoint: ENV.fetch("SEARCH_INDEX_ENDPOINT", DEFAULT_ENDPOINT),
        api_key: self.class.api_key,
        fetcher: JobDiscovery::Fetcher.new
      )
        @provider = provider.to_s
        @endpoint = endpoint
        @api_key = api_key.to_s
        @fetcher = fetcher
      end

      def enabled?
        @api_key.present?
      end

      def search(query, max_results: 10)
        return [] unless enabled?
        raise ArgumentError, "unsupported search index provider: #{@provider}" unless @provider == "serpapi"

        JSON.parse(@fetcher.call(serpapi_url(query, max_results:))).fetch("organic_results", []).filter_map do |item|
          url = item["link"].to_s
          next if url.blank?

          Result.new(url:, title: item["title"].to_s, snippet: item["snippet"].to_s)
        end
      end

      private
        def serpapi_url(query, max_results:)
          uri = URI.parse(@endpoint)
          uri.query = URI.encode_www_form(
            engine: "google",
            q: query,
            api_key: @api_key,
            num: max_results
          )
          uri.to_s
        end
    end
  end
end
