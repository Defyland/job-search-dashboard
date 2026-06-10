require "test_helper"

class JobDiscovery::FetcherTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body, :headers) do
    def [](key)
      (headers || {})[key]
    end
  end

  # Returns each scripted step in order. A step that is an exception class is raised,
  # simulating a network error; anything else is returned as the HTTP response.
  class ScriptedRunner
    attr_reader :calls

    def initialize(steps)
      @steps = steps
      @calls = 0
    end

    def call(_uri, _headers)
      @calls += 1
      step = @steps.shift
      raise step if step.is_a?(Class) && step <= Exception

      step
    end
  end

  class NoJitter
    def rand(_range)
      0.0
    end
  end

  def build_fetcher(steps, sleeps:, **overrides)
    runner = ScriptedRunner.new(steps)
    fetcher = JobDiscovery::Fetcher.new(
      min_request_interval: 0,
      max_retries: 3,
      backoff_base: 0.5,
      max_backoff: 8.0,
      jitter: 0,
      sleeper: ->(seconds) { sleeps << seconds },
      rng: NoJitter.new,
      clock: -> { 0.0 },
      request_runner: runner,
      **overrides
    )
    [ fetcher, runner ]
  end

  test "returns the body on success without retrying or sleeping" do
    sleeps = []
    fetcher, runner = build_fetcher([ FakeResponse.new(200, "ok") ], sleeps:)

    assert_equal "ok", fetcher.call("https://example.com/jobs")
    assert_equal 1, runner.calls
    assert_empty sleeps
  end

  test "retries a transient status with exponential backoff then succeeds" do
    sleeps = []
    fetcher, runner = build_fetcher(
      [ FakeResponse.new(503, ""), FakeResponse.new(200, "ok") ],
      sleeps:
    )

    assert_equal "ok", fetcher.call("https://example.com/jobs")
    assert_equal 2, runner.calls
    assert_equal [ 0.5 ], sleeps
  end

  test "honors the Retry-After header for the backoff delay" do
    sleeps = []
    fetcher, _runner = build_fetcher(
      [ FakeResponse.new(429, "", { "retry-after" => "2" }), FakeResponse.new(200, "ok") ],
      sleeps:
    )

    assert_equal "ok", fetcher.call("https://example.com/jobs")
    assert_equal [ 2.0 ], sleeps
  end

  test "gives up after max_retries on a persistent transient status" do
    sleeps = []
    fetcher, runner = build_fetcher(
      [ FakeResponse.new(503, ""), FakeResponse.new(503, ""), FakeResponse.new(503, "") ],
      sleeps:,
      max_retries: 2
    )

    error = assert_raises(JobDiscovery::Fetcher::RequestError) do
      fetcher.call("https://example.com/jobs")
    end
    assert_equal 503, error.code
    assert_equal 3, runner.calls
    assert_equal [ 0.5, 1.0 ], sleeps
  end

  test "retries a transient network error then succeeds" do
    sleeps = []
    fetcher, runner = build_fetcher(
      [ Timeout::Error, FakeResponse.new(200, "ok") ],
      sleeps:
    )

    assert_equal "ok", fetcher.call("https://example.com/jobs")
    assert_equal 2, runner.calls
    assert_equal [ 0.5 ], sleeps
  end

  test "follows redirects without counting them as retries" do
    sleeps = []
    fetcher, runner = build_fetcher(
      [
        FakeResponse.new(301, "", { "location" => "https://example.com/final" }),
        FakeResponse.new(200, "done")
      ],
      sleeps:
    )

    assert_equal "done", fetcher.call("https://example.com/start")
    assert_equal 2, runner.calls
    assert_empty sleeps
  end

  test "throttles consecutive requests to the same host" do
    sleeps = []
    fetcher, _runner = build_fetcher(
      [ FakeResponse.new(200, "a"), FakeResponse.new(200, "b") ],
      sleeps:,
      min_request_interval: 0.4,
      max_retries: 0
    )

    fetcher.call("https://example.com/one")
    fetcher.call("https://example.com/two")

    assert_equal [ 0.4 ], sleeps
  end
end
