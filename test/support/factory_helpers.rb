module FactoryHelpers
  # Factory creation shortcuts for batch creation and time sequences
  def create_performance_scenario(type: :mixed, count: 10, timeframe: 1.day.ago..Time.current)
    case type
    when :fast
      create_list(:request, count, :fast, occurred_at: random_time_in_range(timeframe))
    when :slow
      create_list(:request, count, :slow, occurred_at: random_time_in_range(timeframe))
    when :critical
      create_list(:request, count, :critical, occurred_at: random_time_in_range(timeframe))
    when :mixed
      fast_count = (count * 0.7).to_i
      slow_count = (count * 0.2).to_i
      critical_count = count - fast_count - slow_count

      [
        create_list(:request, fast_count, :fast, occurred_at: random_time_in_range(timeframe)),
        create_list(:request, slow_count, :slow, occurred_at: random_time_in_range(timeframe)),
        create_list(:request, critical_count, :critical, occurred_at: random_time_in_range(timeframe))
      ].flatten
    end
  end

  def create_hourly_data_series(hours: 24, starting_at: 1.day.ago)
    hours.times.map do |hour|
      time = starting_at + hour.hours
      create(:request, :realistic, occurred_at: time)
    end
  end

  def create_daily_data_series(days: 7, starting_at: 1.week.ago)
    days.times.map do |day|
      time = starting_at + day.days
      create(:request, :realistic, occurred_at: time.beginning_of_day + rand(24).hours)
    end
  end

  # Realistic test data generators using Faker
  def create_realistic_route_set(count: 10)
    count.times.map do
      create(:route, :realistic, method: %w[GET POST PUT DELETE].sample)
    end
  end

  def create_realistic_request_batch(count: 50, routes: nil)
    routes ||= create_realistic_route_set(count: [ count / 5, 3 ].max)

    count.times.map do
      route = routes.sample
      create(:request, :realistic, route: route)
    end
  end

  # Database cleaner integration
  def with_clean_database(&block)
    if defined?(DatabaseCleaner)
      DatabaseCleaner.cleaning(&block)
    else
      # Fallback to manual cleanup
      original_counts = model_counts
      begin
        yield
      ensure
        cleanup_test_data(original_counts)
      end
    end
  end

  def create_with_cleanup(*args, &block)
    with_clean_database do
      if block_given?
        yield
      else
        create(*args)
      end
    end
  end

  # Factory trait patterns for performance scenarios
  def create_threshold_test_data(
    fast_threshold: 100,
    slow_threshold: 500,
    critical_threshold: 1000
  )
    {
      under_fast: create(:request, duration: fast_threshold - 10),
      at_fast: create(:request, duration: fast_threshold),
      over_fast: create(:request, duration: fast_threshold + 10),
      under_slow: create(:request, duration: slow_threshold - 10),
      at_slow: create(:request, duration: slow_threshold),
      over_slow: create(:request, duration: slow_threshold + 10),
      under_critical: create(:request, duration: critical_threshold - 10),
      at_critical: create(:request, duration: critical_threshold),
      over_critical: create(:request, duration: critical_threshold + 10)
    }
  end

  private

  def random_time_in_range(range)
    range.first + rand * (range.last - range.first)
  end

  def model_counts
    {
      requests: RailsPulse::Request.count,
      routes: RailsPulse::Route.count,
      queries: RailsPulse::Query.count,
      operations: RailsPulse::Operation.count
    }
  end

  def cleanup_test_data(original_counts)
    RailsPulse::Request.limit(RailsPulse::Request.count - original_counts[:requests]).delete_all if RailsPulse::Request.count > original_counts[:requests]
    RailsPulse::Route.limit(RailsPulse::Route.count - original_counts[:routes]).delete_all if RailsPulse::Route.count > original_counts[:routes]
    RailsPulse::Query.limit(RailsPulse::Query.count - original_counts[:queries]).delete_all if RailsPulse::Query.count > original_counts[:queries]
    RailsPulse::Operation.limit(RailsPulse::Operation.count - original_counts[:operations]).delete_all if RailsPulse::Operation.count > original_counts[:operations]
  end
end
