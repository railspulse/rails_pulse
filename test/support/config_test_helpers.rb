module ConfigTestHelpers
  # Rails Pulse configuration stubbing
  def stub_rails_pulse_configuration(config_overrides = {})
    default_config = {
      enabled: true,
      route_thresholds: {
        slow: 500,
        very_slow: 1500,
        critical: 3000
      },
      request_thresholds: {
        fast: 100,
        slow: 500,
        critical: 1000
      },
      query_thresholds: {
        fast: 50,
        slow: 200,
        critical: 500
      },
      operation_thresholds: {
        fast: 75,
        slow: 300,
        critical: 750
      },
      max_records: 10000,
      cleanup_after_days: 30,
      track_queries: true,
      track_operations: true
    }

    config = default_config.deep_merge(config_overrides)

    if defined?(Mocha)
      mock_config = mock("rails_pulse_configuration")
      config.each do |key, value|
        mock_config.stubs(key).returns(value)
      end

      # Add missing methods that might be called
      mock_config.stubs(:connects_to).returns(nil)
      mock_config.stubs(:connects_to=).returns(nil)
      mock_config.stubs(:mount_path).returns("/rails_pulse")
      mock_config.stubs(:ignored_routes).returns([])
      mock_config.stubs(:authentication).returns(false)
      mock_config.stubs(:authentication_enabled).returns(false)
      mock_config.stubs(:enabled=).returns(nil)
      mock_config.stubs(:archiving_enabled).returns(true)
      mock_config.stubs(:full_retention_period).returns(30.days)
      mock_config.stubs(:max_table_records).returns({})
      mock_config.stubs(:component_cache_enabled).returns(true)
      mock_config.stubs(:component_cache_duration).returns(1.day)
      mock_config.stubs(:track_assets).returns(false)
      mock_config.stubs(:custom_asset_patterns).returns([])
      mock_config.stubs(:ignored_requests).returns([])
      mock_config.stubs(:route_thresholds).returns({})

      # Add the enabled method that was missing and causing failures
      mock_config.stubs(:enabled).returns(true)

      RailsPulse.stubs(:configuration).returns(mock_config)
      RailsPulse.stubs(:connects_to).returns(nil)
    end

    config
  end

  def stub_rails_pulse_thresholds(request: {}, query: {}, operation: {})
    stub_rails_pulse_configuration(
      request_thresholds: request,
      query_thresholds: query,
      operation_thresholds: operation
    )
  end

  def with_rails_pulse_config(config_overrides = {}, &block)
    original_config = RailsPulse.configuration if defined?(RailsPulse.configuration)

    begin
      stub_rails_pulse_configuration(config_overrides)
      yield
    ensure
      if original_config && defined?(Mocha)
        RailsPulse.stubs(:configuration).returns(original_config)
      end
    end
  end

  # Environment variable test helpers
  def with_env_vars(env_vars = {}, &block)
    original_values = {}

    env_vars.each do |key, value|
      original_values[key] = ENV[key.to_s]
      ENV[key.to_s] = value.to_s
    end

    begin
      yield
    ensure
      original_values.each do |key, value|
        if value.nil?
          ENV.delete(key.to_s)
        else
          ENV[key.to_s] = value
        end
      end
    end
  end

  def stub_database_adapter(adapter_name)
    with_env_vars(DATABASE_ADAPTER: adapter_name) do
      yield
    end
  end

  def stub_rails_env(environment)
    with_env_vars(RAILS_ENV: environment) do
      yield
    end
  end

  # Feature flag testing patterns
  def with_feature_enabled(feature_name, &block)
    config_override = { "#{feature_name}_enabled".to_sym => true }
    with_rails_pulse_config(config_override, &block)
  end

  def with_feature_disabled(feature_name, &block)
    config_override = { "#{feature_name}_enabled".to_sym => false }
    with_rails_pulse_config(config_override, &block)
  end

  def assert_feature_enabled(feature_name)
    config = RailsPulse.configuration
    enabled_key = "#{feature_name}_enabled".to_sym

    assert config.respond_to?(enabled_key), "Feature #{feature_name} not configured"
    assert config.send(enabled_key), "Expected feature #{feature_name} to be enabled"
  end

  def assert_feature_disabled(feature_name)
    config = RailsPulse.configuration
    enabled_key = "#{feature_name}_enabled".to_sym

    assert config.respond_to?(enabled_key), "Feature #{feature_name} not configured"
    assert_not config.send(enabled_key), "Expected feature #{feature_name} to be disabled"
  end

  # Configuration validation helpers
  def assert_valid_threshold_config(thresholds)
    assert thresholds.key?(:fast), "Threshold config missing :fast"
    assert thresholds.key?(:slow), "Threshold config missing :slow"
    assert thresholds.key?(:critical), "Threshold config missing :critical"

    assert thresholds[:fast] < thresholds[:slow], "Fast threshold should be less than slow"
    assert thresholds[:slow] < thresholds[:critical], "Slow threshold should be less than critical"

    assert thresholds[:fast] > 0, "Fast threshold should be positive"
    assert thresholds[:slow] > 0, "Slow threshold should be positive"
    assert thresholds[:critical] > 0, "Critical threshold should be positive"
  end

  def assert_rails_pulse_configured
    assert defined?(RailsPulse), "RailsPulse should be defined"
    assert RailsPulse.respond_to?(:configuration), "RailsPulse should have configuration"

    config = RailsPulse.configuration
    assert_not_nil config, "RailsPulse configuration should not be nil"
  end

  # Test mode helpers
  def in_test_mode(&block)
    with_rails_pulse_config(test_mode: true, &block)
  end

  def in_production_mode(&block)
    with_rails_pulse_config(test_mode: false, &block)
  end

  def with_tracking_disabled(&block)
    with_rails_pulse_config(
      track_queries: false,
      track_operations: false,
      track_requests: false,
      &block
    )
  end

  def with_tracking_enabled(&block)
    with_rails_pulse_config(
      track_queries: true,
      track_operations: true,
      track_requests: true,
      &block
    )
  end
end
