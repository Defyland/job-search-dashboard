require "test_helper"

class Anthropic::MessagesClientTest < ActiveSupport::TestCase
  test "posts a structured tool request and parses tool_use response" do
    response = Net::HTTPSuccess.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(
      :@body,
      JSON.generate(
        {
          "stop_reason" => "tool_use",
          "content" => [
            {
              "type" => "tool_use",
              "name" => "search_profile_intent",
              "input" => {
                "canonical_stacks" => [ "salesforce" ]
              }
            }
          ]
        }
      )
    )

    captured_request = nil
    captured_options = nil
    fake_http = Object.new
    fake_http.define_singleton_method(:request) do |request|
      captured_request = request
      response
    end

    original_start = Net::HTTP.method(:start)
    Net::HTTP.singleton_class.send(:define_method, :start) do |_host, _port, use_ssl:, read_timeout:, open_timeout:, &block|
      captured_options = {
        use_ssl: use_ssl,
        read_timeout: read_timeout,
        open_timeout: open_timeout
      }
      block.call(fake_http)
    end

    begin
      client = Anthropic::MessagesClient.new(api_key: "secret", model: "claude-test", timeout_seconds: 7)
      payload = client.create_structured_output(
        input: [
          { role: "system", content: "system prompt" },
          { role: "user", content: "{\"technology_intent\":\"salesforce\"}" }
        ],
        schema_name: "search_profile_intent",
        schema: {
          type: "object",
          properties: {
            canonical_stacks: {
              type: "array",
              items: { type: "string" }
            }
          }
        }
      )

      assert_equal({ "canonical_stacks" => [ "salesforce" ] }, payload)
    ensure
      Net::HTTP.singleton_class.send(:define_method, :start) do |*args, **kwargs, &block|
        original_start.call(*args, **kwargs, &block)
      end
    end

    assert_equal "secret", captured_request["x-api-key"]
    assert_equal Anthropic::MessagesClient::API_VERSION, captured_request["anthropic-version"]
    assert_equal true, captured_options[:use_ssl]
    assert_equal 7, captured_options[:read_timeout]
    assert_equal 7, captured_options[:open_timeout]

    request_body = JSON.parse(captured_request.body)
    assert_equal "claude-test", request_body["model"]
    assert_equal "system prompt", request_body["system"]
    assert_equal "tool", request_body.dig("tool_choice", "type")
    assert_equal "search_profile_intent", request_body.dig("tool_choice", "name")
    assert_equal "search_profile_intent", request_body.dig("tools", 0, "name")
    assert_equal "{\"technology_intent\":\"salesforce\"}", request_body.dig("messages", 0, "content")
    assert_nil request_body.dig("tools", 0, "strict")
  end
end
