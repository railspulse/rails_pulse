module ChartTestDataFactory
  # Factory methods for generating test scenarios for chart testing

  class << self
    # Create requests distributed evenly across a time range
    def create_even_distribution(start_date: 14.days.ago, end_date: Time.current, requests_per_day: 10)
      route = create_default_route
      requests = []

      (start_date.to_date..end_date.to_date).each do |date|
        requests_per_day.times do |i|
          occurred_at = date.beginning_of_day + (i * (24.0 / requests_per_day)).hours
          duration = generate_realistic_duration

          requests << create_request(
            route: route,
            occurred_at: occurred_at,
            duration: duration
          )
        end
      end

      requests
    end

    # Create sparse data with only some days having requests
    def create_sparse_distribution(start_date: 14.days.ago, end_date: Time.current, active_day_ratio: 0.5)
      route = create_default_route
      requests = []

      total_days = (start_date.to_date..end_date.to_date).count
      active_days = (total_days * active_day_ratio).round

      # Randomly select which days will have data
      all_dates = (start_date.to_date..end_date.to_date).to_a
      active_dates = all_dates.sample(active_days)

      active_dates.each do |date|
        requests_count = rand(1..15) # Random number of requests per active day

        requests_count.times do |i|
          occurred_at = date.beginning_of_day + rand(24).hours + rand(60).minutes
          duration = generate_realistic_duration

          requests << create_request(
            route: route,
            occurred_at: occurred_at,
            duration: duration
          )
        end
      end

      requests
    end

    # Create clustered data (high activity periods)
    def create_clustered_distribution(start_date: 14.days.ago, end_date: Time.current, cluster_count: 3)
      route = create_default_route
      requests = []

      total_days = (start_date.to_date..end_date.to_date).count
      cluster_size = total_days / cluster_count

      cluster_count.times do |cluster_index|
        cluster_start_day = cluster_index * cluster_size
        cluster_days = rand(2..5) # Each cluster spans 2-5 days

        cluster_days.times do |day_offset|
          date = start_date.to_date + cluster_start_day.days + day_offset.days
          next if date > end_date.to_date

          # High activity during cluster periods
          requests_count = rand(20..50)

          requests_count.times do |i|
            occurred_at = date.beginning_of_day + rand(24).hours + rand(60).minutes
            duration = generate_realistic_duration

            requests << create_request(
              route: route,
              occurred_at: occurred_at,
              duration: duration
            )
          end
        end
      end

      requests
    end

    # Create data with linear duration trend (increasing over time)
    def create_linear_duration_trend(start_date: 14.days.ago, end_date: Time.current,
                                   start_duration: 50, end_duration: 200, requests_per_day: 5)
      route = create_default_route
      requests = []

      total_days = (start_date.to_date..end_date.to_date).count
      duration_increment = (end_duration - start_duration).to_f / total_days

      (start_date.to_date..end_date.to_date).each_with_index do |date, day_index|
        base_duration = start_duration + (duration_increment * day_index)

        requests_per_day.times do |i|
          occurred_at = date.beginning_of_day + (i * (24.0 / requests_per_day)).hours
          # Add some variance around the trend
          duration = base_duration + rand(-20..20)
          duration = [ duration, 1 ].max # Ensure positive duration

          requests << create_request(
            route: route,
            occurred_at: occurred_at,
            duration: duration
          )
        end
      end

      requests
    end

    # Create data with exponential duration pattern
    def create_exponential_duration_pattern(start_date: 14.days.ago, end_date: Time.current,
                                          base_duration: 50, growth_factor: 1.1, requests_per_day: 5)
      route = create_default_route
      requests = []

      (start_date.to_date..end_date.to_date).each_with_index do |date, day_index|
        base_duration_for_day = base_duration * (growth_factor ** day_index)

        requests_per_day.times do |i|
          occurred_at = date.beginning_of_day + (i * (24.0 / requests_per_day)).hours
          # Add variance
          duration = base_duration_for_day + rand(-base_duration_for_day * 0.2..base_duration_for_day * 0.2)
          duration = [ duration, 1 ].max

          requests << create_request(
            route: route,
            occurred_at: occurred_at,
            duration: duration
          )
        end
      end

      requests
    end

    # Create performance scenario datasets
    def create_fast_performance_scenario(request_count: 100)
      route = create_default_route

      request_count.times.map do |i|
        occurred_at = rand(14.days).seconds.ago
        duration = rand(1..99) # Fast requests: 1-99ms

        create_request(
          route: route,
          occurred_at: occurred_at,
          duration: duration
        )
      end
    end

    def create_slow_performance_scenario(request_count: 100)
      route = create_default_route

      request_count.times.map do |i|
        occurred_at = rand(14.days).seconds.ago
        duration = rand(100..500) # Slow requests: 100-500ms

        create_request(
          route: route,
          occurred_at: occurred_at,
          duration: duration
        )
      end
    end

    def create_critical_performance_scenario(request_count: 100)
      route = create_default_route

      request_count.times.map do |i|
        occurred_at = rand(14.days).seconds.ago
        duration = rand(500..5000) # Critical requests: 500ms-5s

        create_request(
          route: route,
          occurred_at: occurred_at,
          duration: duration
        )
      end
    end

    def create_mixed_performance_scenario(request_count: 100)
      route = create_default_route

      # 70% fast, 20% slow, 10% critical
      fast_count = (request_count * 0.7).round
      slow_count = (request_count * 0.2).round
      critical_count = request_count - fast_count - slow_count

      requests = []

      # Fast requests
      fast_count.times do
        occurred_at = rand(14.days).seconds.ago
        requests << create_request(
          route: route,
          occurred_at: occurred_at,
          duration: rand(1..99)
        )
      end

      # Slow requests
      slow_count.times do
        occurred_at = rand(14.days).seconds.ago
        requests << create_request(
          route: route,
          occurred_at: occurred_at,
          duration: rand(100..500)
        )
      end

      # Critical requests
      critical_count.times do
        occurred_at = rand(14.days).seconds.ago
        requests << create_request(
          route: route,
          occurred_at: occurred_at,
          duration: rand(500..5000)
        )
      end

      requests
    end

    # Create specific day scenario for detailed testing
    def create_single_day_scenario(date: Time.current.beginning_of_day, durations: [])
      route = create_default_route

      # Use provided durations or generate realistic ones
      test_durations = durations.any? ? durations : generate_realistic_duration_set

      test_durations.map.with_index do |duration, i|
        occurred_at = date + (i * (24.0 / test_durations.length)).hours

        create_request(
          route: route,
          occurred_at: occurred_at,
          duration: duration
        )
      end
    end

    # Create empty scenario (no requests)
    def create_empty_scenario
      # Ensure clean state
      RailsPulse::Request.delete_all
      []
    end

    private

    def create_default_route
      RailsPulse::Route.find_or_create_by(method: "GET", path: "/api/test")
    end

    def create_request(route:, occurred_at:, duration:, status: 200, is_error: false)
      RailsPulse::Request.create!(
        route: route,
        occurred_at: occurred_at,
        duration: duration.round(2),
        status: status,
        is_error: is_error,
        request_uuid: SecureRandom.uuid
      )
    end

    def generate_realistic_duration
      # Generate realistic response times with weighted distribution
      case rand(100)
      when 0..69   # 70% fast responses
        rand(10..150)
      when 70..89  # 20% moderate responses
        rand(150..500)
      when 90..97  # 8% slow responses
        rand(500..2000)
      else         # 2% very slow responses
        rand(2000..10000)
      end
    end

    def generate_realistic_duration_set(count: 20)
      count.times.map { generate_realistic_duration }.sort
    end
  end
end
