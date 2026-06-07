require "json"
require "net/http"

module Anthropic
  class MessagesClient
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class TransientError < Error; end

    API_URL = "https://api.anthropic.com/v1/messages".freeze
    API_VERSION = "2023-06-01".freeze
    DEFAULT_MODEL = "claude-sonnet-4-20250514".freeze
    DEFAULT_TIMEOUT_SECONDS = 20

    attr_reader :model

    def initialize(
      api_key:,
      model: DEFAULT_MODEL,
      timeout_seconds: DEFAULT_TIMEOUT_SECONDS
    )
      raise ConfigurationError, "Missing Anthropic API key." if api_key.blank?

      @api_key = api_key
      @model = model
      @timeout_seconds = [ timeout_seconds.to_i, 1 ].max
    end

    def create_structured_output(input:, schema_name:, schema:, max_output_tokens: 900)
      parsed_body = perform_request(
        model:,
        max_tokens: max_output_tokens,
        system: extract_system_prompt(input),
        messages: build_messages(input),
        tools: [
          {
            name: schema_name,
            description: "Return the compiled search profile payload matching the provided schema.",
            input_schema: schema
          }
        ],
        tool_choice: {
          type: "tool",
          name: schema_name
        }
      )

      extract_structured_output(parsed_body, schema_name:)
    end

    private
      def perform_request(payload)
        uri = URI(API_URL)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: @timeout_seconds, open_timeout: @timeout_seconds) do |http|
          request = Net::HTTP::Post.new(uri)
          request["x-api-key"] = @api_key
          request["anthropic-version"] = API_VERSION
          request["content-type"] = "application/json"
          request.body = JSON.generate(payload)
          http.request(request)
        end

        parsed_body = JSON.parse(response.body)
        return parsed_body if response.is_a?(Net::HTTPSuccess)

        message = parsed_body.dig("error", "message").presence || "Falha ao chamar o Claude (#{response.code})."
        error_class = transient_status_code?(response.code.to_i) ? TransientError : Error
        raise error_class, message
      rescue JSON::ParserError
        raise Error, "O Claude retornou uma resposta invalida."
      rescue Timeout::Error, Errno::ECONNRESET, EOFError, SocketError => error
        raise TransientError, error.message
      end

      def extract_structured_output(parsed_body, schema_name:)
        case parsed_body["stop_reason"]
        when "tool_use"
          tool_use_block = Array(parsed_body["content"]).find { |item| item["type"] == "tool_use" && item["name"] == schema_name }
          raise Error, "O Claude nao retornou a chamada estruturada esperada." if tool_use_block.blank?

          tool_use_block.fetch("input")
        when "refusal"
          raise Error, "O Claude recusou gerar variacoes para este perfil."
        when "max_tokens", "model_context_window_exceeded"
          raise TransientError, "O Claude interrompeu a resposta antes de concluir o payload."
        else
          raise Error, "O Claude nao retornou conteudo estruturado utilizavel."
        end
      end

      def extract_system_prompt(input)
        Array(input).find { |item| item[:role] == "system" || item["role"] == "system" }&.dig(:content) ||
          Array(input).find { |item| item[:role] == "system" || item["role"] == "system" }&.dig("content").to_s
      end

      def build_messages(input)
        Array(input).filter_map do |item|
          role = item[:role] || item["role"]
          next if role == "system"

          {
            role: role,
            content: item[:content] || item["content"]
          }
        end
      end

      def transient_status_code?(status_code)
        status_code == 408 || status_code == 429 || status_code >= 500
      end
  end
end
