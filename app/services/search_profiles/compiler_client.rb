module SearchProfiles
  class CompilerClient
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class TransientError < Error; end

    API_KEY_ENV = "PROFILE_COMPILER_API_KEY".freeze
    LEGACY_API_KEY_ENV = "OPENAI_API_KEY".freeze
    MODEL_ENV = "PROFILE_COMPILER_MODEL".freeze
    TIMEOUT_ENV = "PROFILE_COMPILER_TIMEOUT_SECONDS".freeze
    PROVIDER = "anthropic".freeze
    PROVIDER_LABEL = "Claude".freeze
    DEFAULT_MODEL = Anthropic::MessagesClient::DEFAULT_MODEL
    DEFAULT_TIMEOUT_SECONDS = Anthropic::MessagesClient::DEFAULT_TIMEOUT_SECONDS

    def self.available?
      api_key.present?
    end

    def self.setup_hint
      "Configure a chave do #{PROVIDER_LABEL} em #{API_KEY_ENV} para liberar a geracao automatica de variacoes."
    end

    def self.api_key
      ENV[API_KEY_ENV].presence || ENV[LEGACY_API_KEY_ENV].presence
    end

    attr_reader :model

    def initialize(
      api_key: self.class.api_key,
      model: ENV[MODEL_ENV].presence || DEFAULT_MODEL,
      timeout_seconds: ENV[TIMEOUT_ENV].presence || DEFAULT_TIMEOUT_SECONDS,
      transport: nil
    )
      raise ConfigurationError, self.class.setup_hint if api_key.blank?

      @transport =
        transport || Anthropic::MessagesClient.new(
          api_key:,
          model:,
          timeout_seconds:
        )
      @model = @transport.model
    end

    def provider_name
      PROVIDER
    end

    def create_structured_output(...)
      @transport.create_structured_output(...)
    rescue Anthropic::MessagesClient::ConfigurationError => error
      raise ConfigurationError, error.message
    rescue Anthropic::MessagesClient::TransientError => error
      raise TransientError, error.message
    rescue Anthropic::MessagesClient::Error => error
      raise Error, error.message
    end
  end
end
