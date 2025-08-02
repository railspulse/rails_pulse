module PerformanceTestHelpers
  # Threshold testing patterns
  def assert_performance_threshold(actual_duration, expected_threshold, comparison: :under)
    case comparison
    when :under
      assert actual_duration < expected_threshold,
        "Expected duration #{actual_duration}ms to be under threshold #{expected_threshold}ms"
    when :over
      assert actual_duration > expected_threshold,
        "Expected duration #{actual_duration}ms to be over threshold #{expected_threshold}ms"
    when :at
      assert_equal expected_threshold, actual_duration,
        "Expected duration #{actual_duration}ms to equal threshold #{expected_threshold}ms"
    end
  end

  def assert_fast_request(request, threshold: 100)
    assert_performance_threshold(request.duration, threshold, comparison: :under)
  end

  def assert_slow_request(request, threshold: 500)
    assert_performance_threshold(request.duration, threshold, comparison: :over)
  end

  def assert_critical_request(request, threshold: 1000)
    assert_performance_threshold(request.duration, threshold, comparison: :over)
  end

  # Performance scenario generators
  def create_fast_scenario(count: 10)
    create_list(:request, count, :fast)
  end

  def create_slow_scenario(count: 5)
    create_list(:request, count, :slow)
  end

  def create_critical_scenario(count: 2)
    create_list(:request, count, :critical)
  end

  def create_mixed_performance_scenario(total: 20)
    fast_count = (total * 0.7).to_i
    slow_count = (total * 0.2).to_i
    critical_count = total - fast_count - slow_count

    {
      fast: create_fast_scenario(count: fast_count),
      slow: create_slow_scenario(count: slow_count),
      critical: create_critical_scenario(count: critical_count)
    }
  end

  # Time-based test data creation
  def create_requests_over_time(
    duration: 1.day,
    interval: 1.hour,
    starting_at: 1.day.ago,
    request_traits: [ :realistic ]
  )
    requests = []
    current_time = starting_at
    end_time = starting_at + duration

    while current_time < end_time
      traits = request_traits.dup
      traits << { occurred_at: current_time }
      requests << create(:request, *traits)
      current_time += interval
    end

    requests
  end

  def create_peak_traffic_scenario(peak_hour: 12, base_requests: 5, peak_multiplier: 3)
    24.times.map do |hour|
      request_count = hour == peak_hour ? base_requests * peak_multiplier : base_requests
      time = Time.current.beginning_of_day + hour.hours

      create_list(:request, request_count, occurred_at: time + rand(1.hour))
    end.flatten
  end

  # Metrics calculation test helpers
  def assert_average_duration(requests, expected_average, tolerance: 5)
    actual_average = requests.sum(&:duration) / requests.count.to_f
    assert_in_delta expected_average, actual_average, tolerance,
      "Expected average duration to be around #{expected_average}ms, got #{actual_average}ms"
  end

  def assert_percentile_duration(requests, percentile: 95, expected_duration: nil, max_duration: nil)
    durations = requests.map(&:duration).sort
    index = ((percentile / 100.0) * durations.length).ceil - 1
    actual_percentile = durations[index]

    if expected_duration
      assert_equal expected_duration, actual_percentile,
        "Expected #{percentile}th percentile to be #{expected_duration}ms, got #{actual_percentile}ms"
    end

    if max_duration
      assert actual_percentile <= max_duration,
        "Expected #{percentile}th percentile (#{actual_percentile}ms) to be under #{max_duration}ms"
    end

    actual_percentile
  end

  def assert_error_rate(requests, expected_rate, tolerance: 0.01)
    error_count = requests.count(&:is_error)
    actual_rate = error_count / requests.count.to_f

    assert_in_delta expected_rate, actual_rate, tolerance,
      "Expected error rate to be around #{expected_rate}, got #{actual_rate}"
  end

  # Test-prof integration helpers (when available)
  def with_profiling(type: :memory, &block)
    if defined?(TestProf)
      case type
      when :memory
        TestProf::MemoryProf.profile(&block) if defined?(TestProf::MemoryProf)
      when :time
        TestProf::RubyProf.profile(&block) if defined?(TestProf::RubyProf)
      else
        yield
      end
    else
      yield
    end
  end

  # Benchmark-ips integration for microbenchmarking
  def benchmark_operation(name: "operation", iterations: 100, &block)
    if defined?(Benchmark)
      time = Benchmark.measure { iterations.times(&block) }
      avg_time = time.real / iterations

      puts "#{name}: #{avg_time.round(6)}s average (#{iterations} iterations)"
      avg_time
    else
      yield
      nil
    end
  end

  def assert_performance_improvement(baseline_time, improved_time, min_improvement: 0.1)
    improvement = (baseline_time - improved_time) / baseline_time
    assert improvement >= min_improvement,
      "Expected at least #{(min_improvement * 100).round(1)}% improvement, got #{(improvement * 100).round(1)}%"
  end

  # Memory usage helpers
  def measure_memory_usage(&block)
    if defined?(GC)
      GC.start
      before = GC.stat[:total_allocated_objects]
      yield
      GC.start
      after = GC.stat[:total_allocated_objects]
      after - before
    else
      yield
      nil
    end
  end

  def assert_memory_usage(max_objects: 1000, &block)
    objects_created = measure_memory_usage(&block)

    if objects_created
      assert objects_created <= max_objects,
        "Expected to create at most #{max_objects} objects, created #{objects_created}"
    end

    objects_created
  end
end
