require "test_helper"

class SearchProfiles::CompilerClientTest < ActiveSupport::TestCase
  class FakeTransport
    attr_reader :model

    def initialize(model: "claude-test-model")
      @model = model
    end

    def create_structured_output(**)
      { "ok" => true }
    end
  end

  test "uses the app-level api key env and exposes setup hint" do
    with_env("PROFILE_COMPILER_API_KEY" => "secret", "OPENAI_API_KEY" => nil, "PROFILE_COMPILER_MODEL" => nil, "PROFILE_COMPILER_TIMEOUT_SECONDS" => nil) do
      client = SearchProfiles::CompilerClient.new(transport: FakeTransport.new)

      assert SearchProfiles::CompilerClient.available?
      assert_match "PROFILE_COMPILER_API_KEY", SearchProfiles::CompilerClient.setup_hint
      assert_equal "claude-test-model", client.model
      assert_equal "anthropic", client.provider_name
    end
  end

  test "accepts legacy key env as temporary fallback" do
    with_env("PROFILE_COMPILER_API_KEY" => nil, "OPENAI_API_KEY" => "legacy-secret") do
      assert SearchProfiles::CompilerClient.available?
      assert_equal "legacy-secret", SearchProfiles::CompilerClient.api_key
    end
  end

  test "raises configuration error when api key is missing" do
    with_env("PROFILE_COMPILER_API_KEY" => nil, "OPENAI_API_KEY" => nil) do
      error = assert_raises(SearchProfiles::CompilerClient::ConfigurationError) do
        SearchProfiles::CompilerClient.new
      end

      assert_match "PROFILE_COMPILER_API_KEY", error.message
    end
  end

  private
    def with_env(pairs)
      previous_values = pairs.keys.to_h { |key| [ key, ENV[key] ] }

      pairs.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end

      yield
    ensure
      previous_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
end
