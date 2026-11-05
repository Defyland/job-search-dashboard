require "application_system_test_case"

class SeleniumDetachedNodeTest < ApplicationSystemTestCase
  DETACHED_NODE_ERROR = 'unknown error: unhandled inspector error: {"code":-32000,"message":"Node with given id does not belong to the document"}'
  # chromedriver appends its session line to the message it received in CI.
  CI_DETACHED_NODE_ERROR = "#{DETACHED_NODE_ERROR}\n  (Session info: chrome=156.0.8078.79)"
  EMAIL_FIELD = "input[name='email_address']"

  # Sits between Selenium's bridge and the real HTTP client. While failures remain,
  # script executions answer with the given WebDriver error, which the real Response
  # turns into the exception raised by Bridge#execute.
  class InjectedErrorHttp < SimpleDelegator
    attr_reader :remaining_failures

    def initialize(http, message:, failures:)
      super(http)
      @message = message
      @remaining_failures = failures
    end

    def call(verb, path, command_hash = nil)
      if @remaining_failures.positive? && path.to_s.include?("execute/sync")
        @remaining_failures -= 1
        Selenium::WebDriver::Remote::Response.new(500, { "value" => { "error" => "unknown error", "message" => @message, "stacktrace" => "" } })
      end

      __getobj__.call(verb, path, command_hash)
    end
  end

  test "retries a detached node error raised by the real browser bridge" do
    visit new_session_path

    injector = inject_bridge_error(CI_DETACHED_NODE_ERROR, failures: 1)
    begin
      assert_selector EMAIL_FIELD
    ensure
      restore_bridge_http
    end

    assert_equal 0, injector.remaining_failures
  end

  test "other unknown errors from the real browser bridge still propagate" do
    visit new_session_path

    injector = inject_bridge_error("unknown error: cannot find context with specified id", failures: 1)
    begin
      assert_raises(Selenium::WebDriver::Error::UnknownError) { find(EMAIL_FIELD) }
    ensure
      restore_bridge_http
    end

    assert_equal 0, injector.remaining_failures
  end

  test "a persistent detached node error gives up after Capybara's wait time" do
    visit new_session_path

    inject_bridge_error(CI_DETACHED_NODE_ERROR, failures: Float::INFINITY)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      # Capybara reports a lookup that never recovers as ElementNotFound once the wait expires.
      assert_raises(Capybara::ElementNotFound) { find(EMAIL_FIELD) }
    ensure
      restore_bridge_http
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    assert_operator elapsed, :>=, Capybara.default_max_wait_time
    assert_operator elapsed, :<, Capybara.default_max_wait_time + 10
  end

  private
    def inject_bridge_error(message, failures:)
      bridge = browser_bridge
      @original_http = bridge.http
      bridge.http = InjectedErrorHttp.new(@original_http, message: message, failures: failures)
    end

    # Selenium keeps the bridge private; the test needs it to swap the HTTP client.
    def browser_bridge
      page.driver.browser.send(:bridge)
    end

    def restore_bridge_http
      browser_bridge.http = @original_http
    end
end
