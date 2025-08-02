module PerformanceHelpers
  # Pre-calculated performance data to avoid expensive operations in tests
  SAMPLE_DURATIONS = [ 50, 75, 100, 150, 200, 300, 500, 750, 1000, 1500 ].freeze
  SAMPLE_STATUSES = [ 200, 201, 302, 404, 422, 500 ].freeze
  SAMPLE_PATHS = [ "/api/users", "/api/posts", "/admin/dashboard", "/api/search" ].freeze

  # Create minimal performance data for testing
  def create_sample_requests(count: 5)
    route = rails_pulse_routes(:api_users)
    base_time = 1.hour.ago

    count.times do |i|
      RailsPulse::Request.create!(
        route: route,
        occurred_at: base_time + (i * 10).minutes,
        duration: SAMPLE_DURATIONS.sample,
        status: SAMPLE_STATUSES.sample,
        is_error: [ true, false ].sample,
        request_uuid: SecureRandom.uuid
      )
    end
  end

  # Stub expensive chart calculations
  def stub_chart_calculations
    RailsPulse::Dashboard::Charts::AverageResponseTime.stubs(:call).returns(
      { labels: [ "12:00", "13:00", "14:00" ], data: [ 100, 120, 95 ] }
    )

    RailsPulse::Dashboard::Charts::P95ResponseTime.stubs(:call).returns(
      { labels: [ "12:00", "13:00", "14:00" ], data: [ 250, 300, 275 ] }
    )
  end

  # Stub time-based operations for consistent test results
  def stub_time_operations(fixed_time = Time.current)
    return unless defined?(Mocha)
    Time.stubs(:current).returns(fixed_time)
    Time.stubs(:now).returns(fixed_time)
    DateTime.stubs(:current).returns(fixed_time)
  end

  # Pre-calculated aggregation results to avoid database queries
  def mock_aggregation_results
    {
      average_response_time: 125.5,
      p95_response_time: 300.0,
      error_rate: 2.5,
      request_count: 1250
    }
  end

  # Fast time-series data generation using Timecop
  def generate_time_series_data(start_time, end_time, interval: 1.hour)
    data = []
    current_time = start_time

    while current_time <= end_time
      Timecop.freeze(current_time) do
        data << {
          timestamp: current_time,
          value: block_given? ? yield(current_time) : rand(50..200)
        }
      end
      current_time += interval
    end

    data
  end
end
