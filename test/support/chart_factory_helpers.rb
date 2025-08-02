module ChartFactoryHelpers
  # Create requests for a specific day with given durations
  def create_chart_day_requests(date, durations, route: nil)
    route ||= create(:route)

    durations.map.with_index do |duration, i|
      # Spread requests across the day
      occurred_at = date.beginning_of_day + (i * (24.0 / durations.length)).hours

      create(:chart_request, :at_time, :with_duration,
        route: route,
        at_time: occurred_at,
        with_duration: duration
      )
    end
  end

  # Create requests with even distribution across date range
  def create_even_distribution_requests(start_date:, end_date:, requests_per_day: 5, route: nil)
    route ||= create(:route)

    current_date = start_date.to_date
    end_date = end_date.to_date
    requests = []

    while current_date <= end_date
      requests_per_day.times do |i|
        occurred_at = current_date.beginning_of_day + (i * (24.0 / requests_per_day)).hours
        duration = realistic_duration_for_distribution

        requests << create(:chart_request, :at_time, :with_duration,
          route: route,
          at_time: occurred_at,
          with_duration: duration
        )
      end

      current_date += 1.day
    end

    requests
  end

  # Create sparse distribution (some days have no requests)
  def create_sparse_distribution_requests(start_date:, end_date:, active_day_ratio: 0.3, route: nil)
    route ||= create(:route)

    current_date = start_date.to_date
    end_date = end_date.to_date
    requests = []

    while current_date <= end_date
      # Only create requests on some days based on active_day_ratio
      if rand < active_day_ratio
        request_count = rand(1..8)
        request_count.times do |i|
          occurred_at = current_date.beginning_of_day + (i * (24.0 / request_count)).hours
          duration = realistic_duration_for_distribution

          requests << create(:chart_request, :at_time, :with_duration,
            route: route,
            at_time: occurred_at,
            with_duration: duration
          )
        end
      end

      current_date += 1.day
    end

    requests
  end

  # Create clustered distribution (requests clustered around certain times)
  def create_clustered_distribution_requests(start_date:, end_date:, cluster_count: 2, route: nil)
    route ||= create(:route)

    current_date = start_date.to_date
    end_date = end_date.to_date
    requests = []

    while current_date <= end_date
      cluster_count.times do |cluster|
        # Create cluster around specific hour (e.g., 9am, 2pm)
        cluster_hour = (cluster * 12 / cluster_count + 9) % 24
        cluster_time = current_date.beginning_of_day + cluster_hour.hours

        # Create 3-8 requests around this time
        cluster_size = rand(3..8)
        cluster_size.times do
          # Spread within ±2 hours of cluster time
          occurred_at = cluster_time + rand(-2..2).hours + rand(60).minutes
          duration = realistic_duration_for_distribution

          requests << create(:chart_request, :at_time, :with_duration,
            route: route,
            at_time: occurred_at,
            with_duration: duration
          )
        end
      end

      current_date += 1.day
    end

    requests
  end

  # Create performance scenario data
  def create_performance_scenario_requests(scenario_type, request_count: 50, route: nil)
    route ||= create(:route)
    requests = []

    # Spread requests over the last 2 weeks
    start_time = 14.days.ago.beginning_of_day
    end_time = Time.current

    request_count.times do |i|
      # Spread requests evenly across time range
      occurred_at = start_time + (i * ((end_time - start_time) / request_count))

      duration = case scenario_type
      when :fast
                   rand(1..99)
      when :slow
                   rand(100..500)
      when :critical
                   rand(500..2000)
      when :mixed
                   realistic_duration_for_mixed_scenario
      else
                   rand(50..200)
      end

      requests << create(:chart_request, :at_time, :with_duration,
        route: route,
        at_time: occurred_at,
        with_duration: duration
      )
    end

    requests
  end

  private

  # Generate realistic duration based on weighted distribution
  def realistic_duration_for_distribution
    rand_value = rand
    case rand_value
    when 0..0.7    # 70% fast requests
      rand(10..99)
    when 0.7..0.9  # 20% moderate requests
      rand(100..299)
    when 0.9..0.98 # 8% slow requests
      rand(300..799)
    else           # 2% very slow requests
      rand(800..2000)
    end
  end

  # Generate realistic duration for mixed performance scenarios
  def realistic_duration_for_mixed_scenario
    rand_value = rand
    case rand_value
    when 0..0.5    # 50% fast
      rand(10..99)
    when 0.5..0.8  # 30% moderate
      rand(100..299)
    when 0.8..0.95 # 15% slow
      rand(300..799)
    else           # 5% very slow
      rand(800..2000)
    end
  end

  # Create operations for specific time periods
  def create_operations_for_period(start_date:, end_date:, operations_per_day: 5, query: nil)
    current_date = start_date.to_date
    end_date = end_date.to_date
    operations = []

    while current_date <= end_date
      operations_per_day.times do |i|
        occurred_at = current_date.beginning_of_day + (i * (24.0 / operations_per_day)).hours
        duration = realistic_duration_for_distribution

        operation_attrs = {
          occurred_at: occurred_at,
          duration: duration
        }

        operation_attrs[:query] = query if query

        operations << create(:operation, operation_attrs)
      end

      current_date += 1.day
    end

    operations
  end

  # Create operations with specific durations for a day
  def create_operations_day_requests(date, durations, query: nil)
    durations.map.with_index do |duration, i|
      occurred_at = date.beginning_of_day + (i * (24.0 / durations.length)).hours

      operation_attrs = {
        occurred_at: occurred_at,
        duration: duration
      }

      operation_attrs[:query] = query if query

      create(:operation, operation_attrs)
    end
  end
end
