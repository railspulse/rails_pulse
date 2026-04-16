module RailsPulse
  module Seeds
    module QueryAnalysis
      def self.seed!(queries, routes, historical_start_time, historical_end_time)
        print "Analyzing complex queries"

        ensure_operations_exist(queries, routes, historical_start_time, historical_end_time)
        analyzed_count = analyze_queries

        puts "\nAnalyzed #{analyzed_count} queries with issues/suggestions"
      end

      private

      def self.ensure_operations_exist(queries, routes, start_time, end_time)
        complex_queries = queries.select do |query|
          sql = query.normalized_sql
          is_complex = sql.include?("SELECT *") ||
                      (sql.match?(/^SELECT.*FROM/i) && !sql.include?("WHERE")) ||
                      sql.scan(/\bJOIN\b/i).length > 2 ||
                      sql.include?("(SELECT") ||
                      sql.scan(/\bAND\b|\bOR\b/i).length > 3 ||
                      sql.include?("GROUP BY") ||
                      sql.include?("HAVING")

          is_complex && !query.operations.exists?
        end

        return if complex_queries.empty?

        analytics_route = routes.find { |r| r.path.include?("complex") } || routes.first

        complex_queries.each do |query|
          rand(2..4).times do
            request = ::RailsPulse::Request.create!(
              route: analytics_route,
              duration: rand(300.0..1200.0),
              status: [ 200, 200, 200, 500 ].sample,
              is_error: rand < 0.1,
              request_uuid: SecureRandom.uuid,
              occurred_at: rand(start_time..end_time)
            )

            ::RailsPulse::Operation.create!(
              request: request,
              query: query,
              operation_type: "sql",
              label: query.normalized_sql,
              duration: rand(100.0..400.0),
              codebase_location: [
                "app/controllers/analytics_controller.rb:#{rand(20..80)}",
                "app/controllers/reports_controller.rb:#{rand(15..60)}",
                "app/controllers/dashboard_controller.rb:#{rand(25..90)}"
              ].sample,
              start_time: rand(0..50),
              occurred_at: request.occurred_at
            )
          end
          print "."
        end
      end

      def self.analyze_queries
        complex_queries = ::RailsPulse::Query.joins(:operations).distinct.limit(20)
        analyzed_count = 0

        complex_queries.each do |query|
          begin
            if query.operations.exists?
              ::RailsPulse::QueryAnalysisService.analyze_query(query.id)
              analyzed_count += 1
              print "."
            end
          rescue => e
            # Silently skip analysis failures in seed data
          end
        end

        analyzed_count
      end
    end
  end
end
