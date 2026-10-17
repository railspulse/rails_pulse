require "test_helper"

# The capture decision RequestCollector makes per request when
# config.detail_capture is set (decision 0022).
class RailsPulse::Middleware::DetailCaptureTest < ActiveSupport::TestCase
  def setup
    @original_detail_capture = RailsPulse.configuration.detail_capture
    @payload = nil
    RailsPulse::Tracker.stubs(:track_request).with { |data| @payload = data; true }
  end

  def teardown
    RailsPulse.configuration.detail_capture = @original_detail_capture
  end

  OPERATIONS = [
    { operation_type: "sql", actual_sql: "SELECT * FROM widgets WHERE id = 1", label: "SELECT * FROM widgets WHERE id = 1", duration: 3.0, codebase_location: "app/models/widget.rb:1", start_time: 0.0 },
    { operation_type: "template", label: "widgets/index.html.erb", duration: 2.0 }
  ].freeze

  def call_middleware(status: 200, operations: OPERATIONS)
    app = lambda do |_env|
      RailsPulse::Current.rails_pulse_operations = operations.map(&:dup)
      [ status, { "Content-Length" => "12" }, [ "hello world!" ] ]
    end
    collector = RailsPulse::Middleware::RequestCollector.new(app)
    collector.call(Rack::MockRequest.env_for("/detail-capture-test"))
    @payload
  end

  # Capture Decision Tests

  test "with detail capture off the payload has no detail key and keeps everything" do
    payload = call_middleware

    assert_not payload.key?(:detail)
    assert payload.key?(:request_uuid)
    assert payload.key?(:response_size_bytes)
    assert_equal 2, payload[:operations].size
  end

  test "a request past the threshold keeps full detail" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 100 }
    # A stub app finishes in well under 0.01ms on a fast machine, which the
    # collector rounds to 0, so the clock is fixed: the request takes 250ms.
    Process.stubs(:clock_gettime).returns(10.0, 10.25)

    payload = call_middleware

    assert payload[:detail]
    assert payload.key?(:request_uuid)
    assert_equal 2, payload[:operations].size
  end

  test "a request that ran a slow query keeps full detail" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 10_000_000, queries_slower_than: 50 }
    slow_query = OPERATIONS.first.merge(duration: 50.0)

    payload = call_middleware(operations: [ slow_query, OPERATIONS.last ])

    assert payload[:detail]
    assert_equal 2, payload[:operations].size
  end

  test "a request whose queries are all under queries_slower_than folds" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 10_000_000, queries_slower_than: 50 }
    query = OPERATIONS.first.merge(duration: 49.9)

    payload = call_middleware(operations: [ query, OPERATIONS.last.merge(duration: 500.0) ])

    refute payload[:detail]
  end

  test "a slow query keeps its request at the slow query threshold by default" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 10_000_000 }
    slow_query = OPERATIONS.first.merge(duration: RailsPulse.configuration.query_thresholds[:slow].to_f)

    payload = call_middleware(operations: [ slow_query ])

    assert payload[:detail]
  end

  test "queries_slower_than nil lets a request with a slow query fold" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 10_000_000, queries_slower_than: nil }

    payload = call_middleware(operations: [ OPERATIONS.first.merge(duration: 5_000.0) ])

    refute payload[:detail]
  end

  test "an errored request keeps full detail" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 10_000_000 }

    payload = call_middleware(status: 500)

    assert payload[:detail]
  end

  test "errors false lets an errored fast request fold" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 10_000_000, errors: false }

    payload = call_middleware(status: 500)

    refute payload[:detail]
  end

  test "a sampled request keeps full detail" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 10_000_000, sample_rate: 1.0 }

    payload = call_middleware

    assert payload[:detail]
  end

  test "a fast unsampled request is slimmed to route identity and SQL" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 10_000_000 }

    payload = call_middleware

    refute payload[:detail]
    assert_not payload.key?(:request_uuid)
    assert_not payload.key?(:response_size_bytes)
    assert_equal %w[GET], [ payload[:method] ]
    assert_equal "/detail-capture-test", payload[:path]
    assert_kind_of Numeric, payload[:duration]
    assert_equal 200, payload[:status]

    assert_equal 1, payload[:operations].size
    sql_op = payload[:operations].first

    assert_equal "sql", sql_op[:operation_type]
    assert_equal({ operation_type: "sql", actual_sql: OPERATIONS.first[:actual_sql], label: OPERATIONS.first[:label], duration: 3.0 }, sql_op)
  end

  # Edge Cases

  test "sampling uses Kernel.rand against the configured rate" do
    RailsPulse.configuration.detail_capture = { requests_slower_than: 10_000_000, sample_rate: 0.5 }

    Kernel.stubs(:rand).returns(0.4)

    assert call_middleware[:detail]

    Kernel.stubs(:rand).returns(0.6)

    refute call_middleware[:detail]
  end
end
