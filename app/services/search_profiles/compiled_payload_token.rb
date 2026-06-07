module SearchProfiles
  class CompiledPayloadToken
    STALE_PAYLOAD_MESSAGE = "As variacoes geradas nao correspondem mais aos filtros atuais. Gere novamente antes de salvar.".freeze

    def initialize(verifier: Rails.application.message_verifier("search-profile-compile"))
      @verifier = verifier
    end

    def sign(compiled_payload)
      @verifier.generate(JSON.generate(compiled_payload))
    end

    def verify(token)
      JSON.parse(@verifier.verify(token))
    end

    def verify_for!(token, simple_input:)
      compiled_payload = verify(token)
      expected_fingerprint = SearchProfiles::ProfileBuilder.intent_fingerprint(simple_input)
      return compiled_payload if compiled_payload["request_fingerprint"] == expected_fingerprint

      raise SearchProfiles::IntentCompiler::Error, STALE_PAYLOAD_MESSAGE
    end
  end
end
