require "json"
require "net/http"

module Resend
  class Client
    ENDPOINT = URI("https://api.resend.com/emails")

    def initialize(
      api_key: ENV["RESEND_API_KEY"].presence || ENV["RESEND_API"],
      from_email: ENV["RESEND_FROM"].presence || ENV["RESEND_FROM_EMAIL"]
    )
      @api_key = api_key.to_s
      @from_email = from_email.to_s
    end

    def deliver!(to:, subject:, text:, html:, reply_to: nil)
      raise DeliveryError, "missing_resend_api_key" if api_key.blank?
      raise DeliveryError, "missing_resend_from_email" if from_email.blank?

      request = Net::HTTP::Post.new(ENDPOINT)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = build_payload(to:, subject:, text:, html:, reply_to:).to_json

      response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true) do |http|
        http.request(request)
      end

      return if response.is_a?(Net::HTTPSuccess)

      raise DeliveryError, "resend_#{response.code}"
    rescue Timeout::Error, Errno::ECONNRESET, EOFError, SocketError => error
      raise DeliveryError, error.message
    end

    private
      attr_reader :api_key, :from_email

      def build_payload(to:, subject:, text:, html:, reply_to:)
        {
          from: from_email,
          to: Array(to),
          subject:,
          text:,
          html:
        }.tap do |payload|
          payload[:reply_to] = Array(reply_to).compact_blank if reply_to.present?
        end
      end
  end
end
