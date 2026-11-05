require "application_system_test_case"

class SeleniumDetachedNodeTranslationTest < ActiveSupport::TestCase
  DETACHED_NODE_ERROR = 'unknown error: unhandled inspector error: {"code":-32000,"message":"Node with given id does not belong to the document"}'
  # chromedriver appends its session line to the message it received in CI.
  CI_DETACHED_NODE_ERROR = "#{DETACHED_NODE_ERROR}\n  (Session info: chrome=156.0.8078.79)"

  # Fake HTTP client that answers every request with a WebDriver error payload.
  # The real Selenium::WebDriver::Remote::Response parses it, so the exception
  # is raised by the same bridge code path as in CI.
  class ErrorHttp
    attr_accessor :server_url

    def initialize(message)
      @message = message
    end

    def call(_verb, _path, _body = nil)
      Selenium::WebDriver::Remote::Response.new(500, { "value" => { "error" => "unknown error", "message" => @message, "stacktrace" => "" } })
    end
  end

  setup do
    @bridge = Selenium::WebDriver::Remote::Bridge.new(url: "http://127.0.0.1:9515")
    @bridge.instance_variable_set(:@session_id, "test-session")
  end

  test "detached node error from the bridge becomes StaleElementReferenceError" do
    @bridge.http = ErrorHttp.new(DETACHED_NODE_ERROR)

    error = assert_raises(Selenium::WebDriver::Error::StaleElementReferenceError) do
      @bridge.execute_script("return true;")
    end

    # Selenium appends its troubleshooting link to the message it builds.
    assert error.message.start_with?(DETACHED_NODE_ERROR)
  end

  test "detached node error with the CI session info line becomes StaleElementReferenceError" do
    @bridge.http = ErrorHttp.new(CI_DETACHED_NODE_ERROR)

    assert_raises(Selenium::WebDriver::Error::StaleElementReferenceError) do
      @bridge.execute_script("return true;")
    end
  end

  test "other unknown errors keep propagating as UnknownError" do
    @bridge.http = ErrorHttp.new("unknown error: cannot find context with specified id")

    assert_raises(Selenium::WebDriver::Error::UnknownError) do
      @bridge.execute_script("return true;")
    end
  end

  test "other unknown errors with the CI session info line keep propagating as UnknownError" do
    @bridge.http = ErrorHttp.new("unknown error: cannot find context with specified id\n  (Session info: chrome=156.0.8078.79)")

    assert_raises(Selenium::WebDriver::Error::UnknownError) do
      @bridge.execute_script("return true;")
    end
  end

  test "detached node error followed by unexpected text keeps propagating as UnknownError" do
    @bridge.http = ErrorHttp.new("#{DETACHED_NODE_ERROR}\n  (Session info: chrome=156.0.8078.79) unexpected")

    assert_raises(Selenium::WebDriver::Error::UnknownError) do
      @bridge.execute_script("return true;")
    end
  end

  test "same inspector code with a different message is not translated" do
    @bridge.http = ErrorHttp.new('unknown error: unhandled inspector error: {"code":-32000,"message":"Could not find node with given id"}')

    assert_raises(Selenium::WebDriver::Error::UnknownError) do
      @bridge.execute_script("return true;")
    end
  end
end
