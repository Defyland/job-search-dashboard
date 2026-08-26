require "net/http"

module JobDiscovery
  # HTTP client for the discovery adapters. It is deliberately resilient because the public
  # job sources are flaky and aggressively rate-limited: requests are throttled per host with
  # jitter, transient failures retry with exponential backoff, and `Retry-After` is honored.
  # All delays funnel through an injectable sleeper/clock/rng so the behavior is unit testable.
  class Fetcher
    class RequestError < StandardError
      attr_reader :code

      def initialize(message, code: nil)
        super(message)
        @code = code
      end
    end

    USER_AGENT = "JobSearchDashboardBot/1.0 (+https://web-production-b2243.up.railway.app)".freeze
    RETRYABLE_STATUSES = [ 408, 425, 429, 500, 502, 503, 504 ].freeze
    RETRYABLE_ERRORS = [
      Timeout::Error, Net::OpenTimeout, Net::ReadTimeout,
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
      EOFError, SocketError, IOError
    ].freeze

    def initialize(
      min_request_interval: env_float("SEARCH_MIN_REQUEST_INTERVAL", 0.4),
      max_retries: env_int("SEARCH_MAX_RETRIES", 3),
      backoff_base: env_float("SEARCH_BACKOFF_BASE", 0.5),
      max_backoff: env_float("SEARCH_MAX_BACKOFF", 8.0),
      jitter: env_float("SEARCH_REQUEST_JITTER", 0.4),
      open_timeout: env_float("SEARCH_OPEN_TIMEOUT", 10.0),
      read_timeout: env_float("SEARCH_READ_TIMEOUT", 20.0),
      sleeper: ->(seconds) { sleep(seconds) },
      rng: Random.new,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      request_runner: nil
    )
      @min_request_interval = min_request_interval
      @max_retries = [ max_retries, 0 ].max
      @backoff_base = backoff_base
      @max_backoff = max_backoff
      @jitter = [ jitter, 0.0 ].max
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @sleeper = sleeper
      @rng = rng
      @clock = clock
      @request_runner = request_runner || method(:perform_request)
      @last_request_at = {}
    end

    # `allowed_hosts` pins every hop of a redirect chain to a caller-approved
    # set. Validating only the first URL is not enough: a third-party payload
    # can point at an allowed host that immediately redirects somewhere else.
    def call(url, limit: 5, headers: {}, allowed_hosts: nil)
      raise ArgumentError, "redirect limit reached" if limit <= 0

      uri = URI.parse(url)
      ensure_allowed_host!(uri, allowed_hosts)
      response = resilient_response(uri, headers, body: nil)
      status = response.code.to_i

      case status
      when 200..299
        response.body
      when 300..399
        follow_redirect(url, response, limit:, headers:, allowed_hosts:)
      else
        raise RequestError.new("request failed: #{url} -> #{status}", code: status)
      end
    end

    # Some public endpoints only answer to POST (for example Notion's
    # `loadPageChunk`), so this shares the same throttling, retry and
    # backoff behaviour as `call` instead of opening a bare connection.
    def post(url, body:, headers: {})
      uri = URI.parse(url)
      response = resilient_response(uri, { "Content-Type" => "application/json" }.merge(headers), body:)
      status = response.code.to_i
      return response.body if status.between?(200, 299)

      raise RequestError.new("request failed: #{url} -> #{status}", code: status)
    end

    private
      def resilient_response(uri, headers, body: nil)
        attempt = 0

        loop do
          attempt += 1
          throttle!(uri.host)

          begin
            response = @request_runner.call(uri, headers, body)
          rescue *RETRYABLE_ERRORS => error
            raise error if attempt > @max_retries

            backoff!(attempt)
            next
          end

          if RETRYABLE_STATUSES.include?(response.code.to_i) && attempt <= @max_retries
            backoff!(attempt, retry_after: response["retry-after"])
            next
          end

          return response
        end
      end

      def follow_redirect(url, response, limit:, headers:, allowed_hosts: nil)
        location = response["location"].to_s
        raise RequestError.new("redirect without location: #{url}", code: response.code.to_i) if location.blank?

        call(URI.join(url, location).to_s, limit: limit - 1, headers:, allowed_hosts:)
      end

      def ensure_allowed_host!(uri, allowed_hosts)
        return if allowed_hosts.nil?

        host = uri.host.to_s.downcase.sub(/\Awww\./, "")
        allowed = Array(allowed_hosts).map { |value| value.to_s.downcase.sub(/\Awww\./, "") }
        return if allowed.include?(host)

        raise RequestError.new("host not allowed: #{uri}", code: nil)
      end

      # Keep requests to the same host spaced out with a little jitter so a single scan does not
      # hammer a source and trip its rate limiter.
      def throttle!(host)
        return if @min_request_interval <= 0

        last = @last_request_at[host]
        if last
          wait = @min_request_interval - (@clock.call - last)
          @sleeper.call(wait + jitter_seconds) if wait.positive?
        end
        @last_request_at[host] = @clock.call
      end

      def backoff!(attempt, retry_after: nil)
        base = @backoff_base * (2**(attempt - 1))
        seconds = [ parse_retry_after(retry_after) || base, @max_backoff ].min
        @sleeper.call(seconds + jitter_seconds)
      end

      def jitter_seconds
        return 0.0 if @jitter <= 0

        @rng.rand(0.0..@jitter)
      end

      def parse_retry_after(value)
        return nil if value.blank?
        return Integer(value) if value.to_s.match?(/\A\d+\z/)

        nil
      end

      def perform_request(uri, headers, body = nil)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: @read_timeout, open_timeout: @open_timeout) do |http|
          request = body.nil? ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
          request["User-Agent"] = ENV.fetch("SEARCH_USER_AGENT", USER_AGENT)
          headers.each { |key, value| request[key] = value }
          request.body = body unless body.nil?
          http.request(request)
        end
      end

      def env_float(key, default)
        Float(ENV.fetch(key, default))
      end

      def env_int(key, default)
        Integer(ENV.fetch(key, default))
      end
  end
end
