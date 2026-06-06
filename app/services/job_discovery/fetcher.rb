require "net/http"

module JobDiscovery
  class Fetcher
    USER_AGENT = "JobSearchDashboardBot/1.0 (+https://web-production-b2243.up.railway.app)".freeze

    def call(url, limit: 5, headers: {})
      raise ArgumentError, "redirect limit reached" if limit <= 0

      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 20, open_timeout: 10) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = ENV.fetch("SEARCH_USER_AGENT", USER_AGENT)
        headers.each { |key, value| request[key] = value }
        http.request(request)
      end

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPRedirection
        location = URI.join(url, response["location"]).to_s
        call(location, limit: limit - 1, headers:)
      else
        raise "request failed: #{url} -> #{response.code}"
      end
    end
  end
end
