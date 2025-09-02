module StubHelpers
  # Stub Rails Pulse middleware to avoid actual request collection
  def stub_rails_pulse_middleware
    return unless defined?(Mocha)
    RailsPulse::Middleware::RequestCollector.stubs(:new).returns(mock_middleware)
  end

  # Stub expensive ActiveRecord operations
  def stub_expensive_queries
    return unless defined?(Mocha)
    # Stub groupdate operations
    RailsPulse::Request.stubs(:group_by_hour).returns(mock_grouped_data)
    RailsPulse::Request.stubs(:group_by_day).returns(mock_grouped_data)

    # Stub ransack searches
    RailsPulse::Request.stubs(:ransack).returns(mock_ransack_result)
  end

  # Stub chart data generation
  def stub_chart_data_generation
    return unless defined?(Mocha)
    RailsCharts::BarChart.stubs(:new).returns(mock_chart)
    RailsCharts::LineChart.stubs(:new).returns(mock_chart)
  end

  # Stub file system operations
  def stub_file_operations
    return unless defined?(Mocha)
    File.stubs(:exist?).returns(true)
    File.stubs(:read).returns("{}")
    FileUtils.stubs(:mkdir_p)
  end

  private

  def mock_middleware
    middleware = mock("middleware")
    middleware.stubs(:call).returns([ 200, {}, [ "OK" ] ])
    middleware
  end

  def mock_grouped_data
    {
      Time.current => 100,
      1.hour.ago => 120,
      2.hours.ago => 95
    }
  end

  def mock_ransack_result
    result = mock("ransack_result")
    result.stubs(:result).returns(RailsPulse::Request.none)
    result
  end

  def mock_chart
    chart = mock("chart")
    chart.stubs(:to_html).returns("<div>Mock Chart</div>")
    chart.stubs(:data).returns([ 100, 120, 95 ])
    chart.stubs(:js_code).returns("console.log('mock chart');")
    chart.stubs(:to_s).returns("<div>Mock Chart</div>")
    chart
  end

  # Comprehensive stubbing for unit tests
  def stub_all_external_dependencies
    # Note: configuration stubbing is handled by test_helper setup
    stub_expensive_queries
    stub_chart_data_generation
    stub_file_operations
  end
end
