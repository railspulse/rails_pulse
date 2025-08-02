module BulkDataHelpers
  # Generate comprehensive test data for system tests
  def generate_bulk_test_data(options = {})
    routes_count = options[:routes_count] || 25
    requests_per_week = options[:requests_per_week] || 50
    queries_count = options[:queries_count] || 30
    weeks_back = options[:weeks_back] || 2

    # Create diverse routes
    routes = routes_count.times.map do
      create(:route, :realistic_api)
    end

    # Create diverse queries
    queries = queries_count.times.map do
      create(:query, :realistic_sql)
    end

    # Generate requests for multiple time periods, focusing on recent data
    weeks_back.times do |week_offset|
      case week_offset
      when 0
        # Recent period (last 22 hours): Most data for default view - ensure it's within 24h filter
        week_requests = (requests_per_week * 0.8).to_i
        time_start = 22.hours.ago  # Well within the 24 hour default filter
        time_end = 1.hour.ago      # Recent but not too recent
      when 1
        # Last week: Some data for week-over-week comparison
        week_requests = (requests_per_week * 0.2).to_i
        time_start = 1.week.ago
        time_end = 1.week.ago + 8.hours  # Shorter time window
      else
        # Earlier periods: minimal data
        week_requests = 3
        time_start = week_offset.weeks.ago
        time_end = week_offset.weeks.ago + 2.hours
      end

      week_requests.times do
        route = routes.sample
        occurred_at = time_start + rand((time_end - time_start).seconds)

        request = create(:request,
          :performance_varied,
          route: route,
          occurred_at: occurred_at
        )

        # Create 1-3 operations per request
        rand(1..3).times do
          query = queries.sample
          op_duration = rand(10..[ request.duration/2, 10 ].max)

          create(:operation,
            request: request,
            query: query,
            operation_type: "sql",
            label: "Query for #{route.path}",
            duration: op_duration,
            start_time: request.occurred_at.to_f,
            occurred_at: request.occurred_at
          )
        end
      end
    end

    {
      routes: routes,
      queries: queries,
      total_requests: weeks_back * requests_per_week
    }
  end

  # Generate data specifically for pagination testing (20+ records per page)
  def generate_pagination_test_data
    generate_bulk_test_data(
      routes_count: 25,
      requests_per_week: 60, # Ensures 20+ requests per page
      queries_count: 30,
      weeks_back: 2
    )
  end

  # Generate data for week-over-week comparison testing
  def generate_weekly_comparison_data
    generate_bulk_test_data(
      routes_count: 15,
      requests_per_week: 40,
      queries_count: 20,
      weeks_back: 3 # This week, last week, and week before
    )
  end

  # Create focused data for specific performance scenarios
  def generate_performance_scenario_data
    # Create routes with known performance characteristics
    fast_route = create(:route, :fast_endpoint, path: "/api/fast")
    slow_route = create(:route, :slow_endpoint, path: "/api/slow")
    critical_route = create(:route, :critical_endpoint, path: "/api/critical")

    # Create queries with known patterns
    simple_query = create(:query, :select_query)
    complex_query = create(:query, :complex_realistic)

    # Generate predictable request patterns
    [ 1.week.ago, Time.current ].each do |base_time|
      # Fast requests
      20.times do
        request = create(:request, :fast, route: fast_route, occurred_at: base_time + rand(7.days))
        create(:operation, request: request, query: simple_query, duration: rand(1..50))
      end

      # Slow requests
      15.times do
        request = create(:request, :slow, route: slow_route, occurred_at: base_time + rand(7.days))
        create(:operation, request: request, query: complex_query, duration: rand(100..300))
      end

      # Critical requests
      5.times do
        request = create(:request, :critical, route: critical_route, occurred_at: base_time + rand(7.days))
        create(:operation, request: request, query: complex_query, duration: rand(500..1000))
      end
    end

    {
      fast_route: fast_route,
      slow_route: slow_route,
      critical_route: critical_route,
      simple_query: simple_query,
      complex_query: complex_query
    }
  end
end
