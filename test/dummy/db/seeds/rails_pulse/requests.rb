module RailsPulse
  module Seeds
    module Requests
      def self.seed!(routes, queries, request_count: 5000)
        print "Generating #{request_count} requests"

        start_time = SeedConfig.days_ago.days.ago

        # 6-hour performance issue period (2 weeks ago, only if we have enough history)
        slowdown_start = nil
        slowdown_end = nil
        if SeedConfig.days_ago >= 14
          slowdown_start = 2.weeks.ago + 14.hours
          slowdown_end = slowdown_start + 6.hours
        end

        requests_created = []
        request_count.times do |i|
          route = select_route(routes, i, request_count)
          occurred_at = rand(start_time..Time.current)

          duration = calculate_duration(route, occurred_at, slowdown_start, slowdown_end)
          is_error, status = determine_status(route)

          response_size = calculate_response_size(route, status)

          request = ::RailsPulse::Request.create!(
            route: route,
            method: route.http_methods_list.first,
            duration: duration,
            status: status,
            is_error: is_error,
            request_uuid: SecureRandom.uuid,
            controller_action: SeedHelpers.controller_action_for(route),
            occurred_at: occurred_at,
            response_size_bytes: response_size
          )

          create_operations(request, route, queries, occurred_at)
          requests_created << request

          print "." if i % (request_count / 50).ceil == 0
        end

        puts "\nCreated #{requests_created.count} requests with #{::RailsPulse::Operation.count} operations"
        requests_created
      end

      private

      def self.select_route(routes, index, total)
        # 40% chance to select long paths (if they exist) to make them prominent
        if index % 10 < 4
          long_paths = routes.select { |r| r.path.length > 80 }
          long_paths.any? ? long_paths.sample : routes.sample
        else
          routes.sample
        end
      end

      def self.calculate_duration(route, occurred_at, slowdown_start, slowdown_end)
        base = case route.path
        when "/"           then rand(45..110)
        when "/fast"       then rand(5..18)
        when "/slow"       then rand(190..460)
        when "/error_prone" then rand(20..90)
        when "/search"     then rand(50..160)
        when "/api_simple" then rand(8..28)
        when "/api_complex" then rand(90..220)
        when "/sign_in"    then rand(30..80)
        when "/up", "/health", "/robots.txt" then rand(1..5)
        else
                 if route.path.include?("/rails/active_storage/")
                   rand(70..180)
                 elsif route.path.include?("/api/v2/organizations/")
                   rand(60..160)
                 elsif route.path.include?("/webhooks/")
                   rand(35..110)
                 elsif route.path.include?("/admin/system/configuration/")
                   rand(110..280)
                 else
                   rand(15..65)
                 end
        end

        duration = base + rand(-base * 0.3..base * 0.5)
        duration = [ duration, 10 ].max

        # 3× slowdown during performance incident (if configured)
        if slowdown_start && slowdown_end && occurred_at >= slowdown_start && occurred_at <= slowdown_end
          duration *= 3.0
        end
        duration
      end

      def self.calculate_response_size(route, status)
        # Error responses are small (just an error page/body)
        return rand(500..3_000) if status >= 400

        base = case route.path
        when "/"            then rand(8_000..25_000)   # Full HTML page
        when "/fast"        then rand(500..2_000)       # Minimal response
        when "/slow"        then rand(50_000..200_000)  # Large payload (why it's slow)
        when "/error_prone" then rand(1_000..8_000)
        when "/search"      then rand(15_000..60_000)   # Search results page
        when "/api_simple"  then rand(200..2_000)       # Small JSON
        when "/api_complex" then rand(10_000..80_000)   # Large JSON payload
        when "/sign_in"     then rand(3_000..12_000)    # Login form / redirect
        when "/up", "/health", "/robots.txt" then rand(20..200) # Tiny health/static response
        else
          if route.path.include?("/rails/active_storage/")
            rand(20_000..5_000_000)   # File downloads vary widely
          elsif route.path.include?("/api/v2/organizations/")
            rand(5_000..40_000)       # API JSON response
          elsif route.path.include?("/webhooks/")
            rand(100..1_000)          # Webhook acknowledgement
          elsif route.path.include?("/admin/system/configuration/")
            rand(20_000..80_000)      # Admin page with lots of data
          else
            rand(3_000..20_000)
          end
        end

        # Add ±20% jitter
        jitter = rand(-base * 0.2..base * 0.2).to_i
        [ base + jitter, 100 ].max
      end

      def self.determine_status(route)
        error_roll = case route.path
        when "/error_prone" then rand < 0.04
        else rand < 0.005
        end

        status = error_roll ? [ 400, 404, 422, 500, 503 ].sample : [ 200, 201, 204 ].sample
        is_error = status >= 500
        [ is_error, status ]
      end

      def self.create_operations(request, route, queries, occurred_at)
        operation_count = case route.path
        when "/"           then rand(8..15)
        when "/fast"       then rand(1..3)
        when "/slow"       then rand(15..30)
        when "/error_prone" then rand(5..20)
        when "/search"     then rand(6..12)
        when "/api_complex" then rand(10..25)
        else rand(3..8)
        end

        current_time = 0.0
        operation_count.times do
          operation_type = [ "sql", "template", "controller" ].sample
          operation_duration = case operation_type
          when "sql"        then rand(1..35)
          when "template"   then rand(5..40)
          when "controller" then request.duration
          end

          query = select_query(queries, operation_type)
          location = codebase_location(operation_type, query, route, request)

          attrs = {
            request: request,
            operation_type: operation_type,
            duration: operation_duration,
            codebase_location: location,
            start_time: current_time,
            occurred_at: occurred_at
          }

          if operation_type == "sql"
            attrs[:actual_sql] = query&.normalized_sql
          else
            attrs[:label] = operation_label(operation_type, request)
          end

          ::RailsPulse::Operation.create!(attrs)

          current_time += operation_duration
        end
      end

      def self.select_query(queries, operation_type)
        return nil unless operation_type == "sql"

        # 70% complex queries for interesting analysis
        if rand < 0.7
          complex = queries.select do |q|
            sql = q.normalized_sql
            sql.include?("SELECT *") ||
              (sql.match?(/^SELECT.*FROM/i) && !sql.include?("WHERE")) ||
              sql.scan(/\bJOIN\b/i).length > 2 ||
              sql.include?("(SELECT") ||
              sql.scan(/\bAND\b|\bOR\b/i).length > 3
          end
          complex.any? ? complex.sample : queries.sample
        else
          queries.sample
        end
      end

      def self.operation_label(operation_type, request)
        case operation_type
        when "template"   then [ "layouts/application", "home/index", "posts/show", "users/index" ].sample
        when "controller" then request.controller_action
        end
      end

      def self.codebase_location(operation_type, query, route, request)
        case operation_type
        when "sql"       then sql_location(query)
        when "template"  then "app/views/#{route.path.split('/').reject(&:empty?).first || 'home'}/index.html.erb:#{rand(1..20)}"
        when "controller" then "app/controllers/#{route.path.split('/').reject(&:empty?).first || 'home'}_controller.rb:#{rand(5..75)}"
        else "app/controllers/application_controller.rb:10"
        end
      end

      def self.sql_location(query)
        return "app/models/application_record.rb:12" unless query

        case query.normalized_sql
        when /SELECT id, name, email FROM users WHERE id = \?/
          "app/models/user.rb:15"
        when /SELECT \* FROM posts WHERE user_id = \?/
          "app/models/user.rb:23"
        when /COUNT\(\*\) FROM comments/
          "app/models/post.rb:18"
        when /INSERT INTO posts/
          "app/models/post.rb:8"
        when /UPDATE posts SET title/
          "app/models/post.rb:35"
        when /DELETE FROM posts/
          "app/models/post.rb:42"
        when /SELECT \* FROM users WHERE id = \?/
          "app/models/user.rb:18"
        when /SELECT name FROM users$/
          "app/controllers/admin_controller.rb:67"
        when /title LIKE.*content LIKE/
          "app/controllers/search_controller.rb:12"
        when /LEFT JOIN.*LEFT JOIN.*WHERE.*AND.*OR/
          "app/controllers/analytics_controller.rb:45"
        when /COUNT\(DISTINCT posts\.id\)/
          "app/controllers/dashboard_controller.rb:78"
        when /UPDATE posts SET view_count/
          "app/models/post.rb:67"
        when /DELETE FROM comments WHERE created_at/
          "app/jobs/cleanup_job.rb:23"
        else
          "app/models/application_record.rb:12"
        end
      end
    end
  end
end
