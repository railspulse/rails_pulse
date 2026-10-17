require "test_helper"

# The capture decision RequestCollector makes per request when
# config.store_full_details names a threshold (decision 0022).
class RailsPulse::Middleware::DetailCaptureTest < ActiveSupport::TestCase
  CAPTURE_SETTINGS = %i[store_full_details request_thresholds query_thresholds].freeze

  def setup
    config = RailsPulse.configuration
    @original_settings = CAPTURE_SETTINGS.index_with { |key| config.public_send(key) }
    @payload = nil
    RailsPulse::Tracker.stubs(:track_request).with { |data| @payload = data; true }
  end

  def teardown
    @original_settings.each { |key, value| RailsPulse.configuration.public_send("#{key}=", value) }
  end

  # Full details above :slow, with slow thresholds nothing here reaches
  # unless a test lowers one.
  def capture(request_slow: 10_000_000, query_slow: 10_000_000, sample_rate: 0)
    config = RailsPulse.configuration
    config.request_thresholds = config.request_thresholds.merge(slow: request_slow)
    config.query_thresholds = config.query_thresholds.merge(slow: query_slow)
    config.store_full_details = { above: :slow, sample_rate: sample_rate }
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

  test "with store_full_details :all the payload has no detail key and keeps everything" do
    payload = call_middleware

    assert_not payload.key?(:detail)
    assert payload.key?(:request_uuid)
    assert payload.key?(:response_size_bytes)
    assert_equal 2, payload[:operations].size
  end

  test "a request past the slow request threshold keeps full detail" do
    capture(request_slow: 100)
    # A stub app finishes in well under 0.01ms on a fast machine, which the
    # collector rounds to 0, so the clock is fixed: the request takes 250ms.
    Process.stubs(:clock_gettime).returns(10.0, 10.25)

    payload = call_middleware

    assert payload[:detail]
    assert payload.key?(:request_uuid)
    assert_equal 2, payload[:operations].size
  end

  test "a request that ran a query at the slow query threshold keeps full detail" do
    capture(query_slow: 50)
    slow_query = OPERATIONS.first.merge(duration: 50.0)

    payload = call_middleware(operations: [ slow_query, OPERATIONS.last ])

    assert payload[:detail]
    assert_equal 2, payload[:operations].size
  end

  test "a request whose queries are all under the slow query threshold folds" do
    capture(query_slow: 50)
    query = OPERATIONS.first.merge(duration: 49.9)

    payload = call_middleware(operations: [ query, OPERATIONS.last.merge(duration: 500.0) ])

    refute payload[:detail]
  end

  test "an errored request keeps full detail" do
    capture

    payload = call_middleware(status: 500)

    assert payload[:detail]
  end

  test "a sampled request keeps full detail" do
    capture(sample_rate: 1.0)

    payload = call_middleware

    assert payload[:detail]
  end

  test "a fast unsampled request is slimmed to route identity and SQL" do
    capture

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
    capture(sample_rate: 0.5)

    Kernel.stubs(:rand).returns(0.4)

    assert call_middleware[:detail]

    Kernel.stubs(:rand).returns(0.6)

    refute call_middleware[:detail]
  end
end
