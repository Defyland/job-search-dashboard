require "test_helper"

class Resend::ClientTest < ActiveSupport::TestCase
  test "deliver uses legacy env aliases and forwards reply_to" do
    http = FakeHttp.new

    with_env("RESEND_API" => "legacy-api-key", "RESEND_FROM_EMAIL" => "Farol <onboarding@resend.dev>") do
      with_replaced_singleton_method(Net::HTTP, :start, ->(*, **, &block) { block.call(http) }) do
        Resend::Client.new.deliver!(
          to: "owner@example.com",
          reply_to: "lead@example.com",
          subject: "Nova inscricao",
          text: "texto",
          html: "<p>html</p>"
        )
      end
    end

    payload = JSON.parse(http.last_request.body)

    assert_equal "Bearer legacy-api-key", http.last_request["Authorization"]
    assert_equal "Farol <onboarding@resend.dev>", payload.fetch("from")
    assert_equal [ "owner@example.com" ], payload.fetch("to")
    assert_equal [ "lead@example.com" ], payload.fetch("reply_to")
  end

  test "deliver raises when resend configuration is missing" do
    error = assert_raises(Resend::DeliveryError) do
      Resend::Client.new(api_key: nil, from_email: nil).deliver!(
        to: "owner@example.com",
        subject: "Nova inscricao",
        text: "texto",
        html: "<p>html</p>"
      )
    end

    assert_equal "missing_resend_api_key", error.message
  end

  private
    def with_replaced_singleton_method(klass, method_name, replacement)
      singleton_class = klass.singleton_class
      original_method = singleton_class.instance_method(method_name)

      singleton_class.define_method(method_name) do |*args, **kwargs, &block|
        replacement.call(*args, **kwargs, &block)
      end

      yield
    ensure
      singleton_class.define_method(method_name, original_method)
    end

    def with_env(overrides)
      previous_values = overrides.keys.to_h { |key| [ key, ENV[key] ] }
      overrides.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous_values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end

    class FakeHttp
      attr_reader :last_request

      def request(request)
        @last_request = request
        SuccessResponse.new
      end
    end

    class SuccessResponse
      def code
        "200"
      end

      def is_a?(klass)
        klass == Net::HTTPSuccess || super
      end
    end
end
