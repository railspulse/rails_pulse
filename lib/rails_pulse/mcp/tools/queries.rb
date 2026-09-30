module RailsPulse
  module Mcp
    module Tools
      class Queries < ::MCP::Tool
        extend Helpers

        SQL_LENGTH = 300
        MAX_PAGE = 500

        tool_name "rails_pulse_queries"
        description "Find the most expensive SQL queries for a time period: execution count, average/max/total time, " \
                    "and N+1 detection. Use this to see which queries are worth optimising."

        annotations(
          read_only_hint: true,
          destructive_hint: false,
          open_world_hint: false
        )

        input_schema(
          properties: {
            **Helpers.window_properties("last_24_hours"),
            limit: {
              type: "integer",
              description: "Maximum number of queries (1-50)",
              default: 10
            },
            sort: {
              type: "string",
              description: "Order by 'total_duration' (default), 'avg_duration', 'max_duration', or 'executions'",
              default: "total_duration"
            },
            n_plus_one_only: {
              type: "boolean",
              description: "Only return queries flagged as likely N+1",
              default: false
            },
            # rails_pulse_endpoint and rails_pulse_slow_requests hand back an
            # integer route_id, so the next call passes a number.
            route: {
              type: %w[integer string],
              description: "Restrict to SQL issued while serving one endpoint. A route_id from rails_pulse_routes " \
                           "or rails_pulse_slow_requests, or a controller action or path to match on."
            }
          }
        )

        def self.call(period: "last_24_hours", limit: 10, sort: "total_duration", n_plus_one_only: false, route: nil, server_context:, **options)
          respond(server_context) do |client|
            window = resolve_window(period: period, since: options[:since], until_time: options[:until])
            limit = limit.to_i.clamp(1, 50)
            # The N+1 flag is filtered here, not by the API, so fetch the
            # largest page it allows and keep the first `limit` matches.
            page = n_plus_one_only ? MAX_PAGE : limit
            params = window_params(window).merge(sort: sort, limit: page)
            params[:route] = route if route
            result = client.get("/queries", params)

            queries = (result["data"] || []).map { |q| format_query(q) }
            queries = queries.select { |q| q[:n_plus_one][:likely] }.first(limit) if n_plus_one_only

            payload = {
              window: window,
              sort: sort,
              total_queries: result.dig("meta", "total") || queries.size,
              queries: queries,
              summary: build_summary(queries),
              next_steps: build_next_steps(queries)
            }
            payload[:route] = route if route
            payload
          end
        end

        # Transaction control repeats within a request by design; it is never
        # an N+1 however often it appears.
        TRANSACTION_STATEMENT = /\A(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)\b/i

        private_class_method def self.format_query(query)
          stats = query["stats"] || {}
          analysis = query["n_plus_one"] || {}
          repetition = stats["max_repetition_count"].to_i
          sql = query["normalized_sql"].to_s.gsub(/\s+/, " ").strip
          repeated = repetition > 1 && !sql.match?(TRANSACTION_STATEMENT)

          {
            id: query["id"],
            sql: truncate(sql, SQL_LENGTH),
            executions: stats["executions"],
            avg_duration_ms: stats["avg_duration_ms"],
            max_duration_ms: stats["max_duration_ms"],
            total_duration_ms: stats["total_duration_ms"],
            n_plus_one: {
              likely: analysis["likely"] == true || repeated,
              confidence: analysis["confidence"],
              max_repetition_count: repetition > 0 ? repetition : nil
            },
            issue_count: Array(query["issues"]).size,
            suggestions: Array(query["suggestions"]),
            # Where the query was issued from, most frequent first, so the
            # investigation reaches the code rather than stopping at the SQL.
            source_locations: Array(stats["source_locations"])
          }
        end

        private_class_method def self.build_summary(queries)
          return "No query activity found for this period." if queries.empty?

          top = queries.first
          n_plus_one = queries.count { |q| q[:n_plus_one][:likely] }
          parts = [ "Top query by #{top[:executions]} executions / #{top[:total_duration_ms]}ms total: #{truncate(top[:sql], 80)}" ]
          parts << "#{n_plus_one} likely N+1 quer#{n_plus_one == 1 ? 'y' : 'ies'}" if n_plus_one > 0
          parts.join(". ") + "."
        end

        private_class_method def self.build_next_steps(queries)
          steps = []
          if queries.any? { |q| q[:n_plus_one][:likely] }
            steps << "N+1 candidates: find the call site and preload the association (`includes`/`preload`) or batch the lookup."
          end
          if queries.any? { |q| q[:avg_duration_ms].to_f > 100 }
            steps << "Queries averaging over 100ms: check `suggestions` for missing indexes and run EXPLAIN on the normalized SQL."
          end
          if queries.any? { |q| q[:executions].to_i > 1000 && q[:avg_duration_ms].to_f < 5 }
            steps << "Very frequent fast queries add up — consider caching or reducing calls per request."
          end
          if queries.any? { |q| q[:source_locations].any? }
            steps << "source_locations names the file and line each query was issued from — start there rather than searching for the SQL."
          end
          steps << "Use rails_pulse_endpoint to see which endpoints are slow and correlate with these queries."
          steps
        end
      end
    end
  end
end
