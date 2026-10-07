require "test_helper"

module RailsPulse
  module Cloud
    class SummaryItemsTest < ActiveSupport::TestCase
      fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_jobs, :rails_pulse_exception_groups, :rails_pulse_requests

      setup do
        Summary.delete_all
        Operation.delete_all
        @hour = 2.hours.ago.beginning_of_hour
        @no_patterns = RoutePattern.new([])
        summary("RailsPulse::Request", 0, count: 10, status_2xx: 8, status_4xx: 1, status_5xx: 1, error_count: 1)
      end

      # Structure Tests

      test "an hour SummaryJob has not written has no items" do
        Summary.delete_all

        assert_empty items
      end

      test "the whole application's traffic is one requests item" do
        requests = items.find { |item| item[:kind] == "requests" }

        assert_equal "summary", requests[:type]
        assert_equal @hour.utc.iso8601, requests[:period_start]
        assert_equal 10, requests[:count]
        assert_equal [ 8, 1, 1, 1 ], requests.values_at(:status_2xx, :status_4xx, :status_5xx, :error_count)
      end

      test "a route is named by its path, controller action and methods, never its id or tags" do
        route = rails_pulse_routes(:api_users)
        summary("RailsPulse::Route", route.id, count: 4)
        item = items.find { |candidate| candidate[:kind] == "route" }

        assert_equal "/api/users", item[:path]
        assert_equal "api/users#index", item[:controller_action]
        assert_equal route.http_methods_list, item[:http_methods]
        assert_equal 4, item[:count]
        assert_empty item.keys & %i[id route_id summarizable_id tags]
      end

      test "routes stored under two paths with one pattern are sent as one item" do
        routes = ActionDispatch::Routing::RouteSet.new
        routes.draw { get "/posts/:id(.:format)", to: "posts#show" }
        html = Route.create!(http_methods: '["GET"]', path: "/posts/:id", controller_action: "posts#show")
        json = Route.create!(http_methods: '["GET"]', path: "/posts/:id.json", controller_action: "posts#show")
        summary("RailsPulse::Route", html.id, count: 3, avg: 10.0)
        summary("RailsPulse::Route", json.id, count: 1, avg: 30.0)

        route_items = items(route_patterns: RoutePattern.new(routes.routes)).select { |item| item[:kind] == "route" }

        assert_equal 1, route_items.size
        assert_equal "/posts/:id", route_items.first[:path]
        assert_equal 4, route_items.first[:count]
        assert_in_delta 15.0, route_items.first[:avg_duration]
      end

      test "requests no route matched are grouped by path prefix" do
        [ "/wp-admin/setup.php", "/wp-admin/install.php", "/wp-login.php" ].each_with_index do |path, index|
          route = Route.create!(http_methods: '["GET"]', path: path, controller_action: nil)
          summary("RailsPulse::Route", route.id, count: index + 1, status_4xx: index + 1)
        end
        unmatched = items.select { |item| item[:kind] == "unmatched" }

        assert_equal [ [ "/wp-admin/*", 3 ], [ "/wp-login.php", 3 ] ], unmatched.map { |item| item.values_at(:path_prefix, :count) }.sort
        assert(unmatched.none? { |item| item.key?(:path) })
      end

      # Calculation Tests

      test "unmatched prefixes past the busiest are combined under *" do
        [ [ "/a.php", 5 ], [ "/b.php", 2 ], [ "/c.php", 1 ] ].each do |path, count|
          route = Route.create!(http_methods: '["GET"]', path: path, controller_action: nil)
          summary("RailsPulse::Route", route.id, count: count, status_4xx: count)
        end
        unmatched = items(limits: { unmatched: 1 }).select { |item| item[:kind] == "unmatched" }

        assert_equal [ [ "/a.php", 5 ], [ "*", 3 ] ], unmatched.map { |item| item.values_at(:path_prefix, :count) }
        assert_equal 3, unmatched.last[:status_4xx]
      end

      test "routes past the limit are combined under *, keeping the most total time" do
        summary("RailsPulse::Route", rails_pulse_routes(:api_users).id, count: 10, avg: 100.0)
        summary("RailsPulse::Route", rails_pulse_routes(:api_posts).id, count: 100, avg: 50.0)
        summary("RailsPulse::Route", rails_pulse_routes(:api_test).id, count: 1, avg: 1.0)
        route_items = items(limits: { route: 1 }).select { |item| item[:kind] == "route" }

        assert_equal [ "/api/posts", "*" ], route_items.map { |item| item[:path] }
        assert_equal 11, route_items.last[:count]
        assert_nil route_items.last[:controller_action]
      end

      test "a query is named by its hash, label, shape and call sites" do
        query = rails_pulse_queries(:simple_query)
        summary("RailsPulse::Query", query.id, count: 7)
        operation(query, "app/models/user.rb:12", times: 3)
        operation(query, "app/controllers/users_controller.rb:8", times: 2)
        operation(query, "app/jobs/sync_job.rb:4", times: 1)
        item = items.find { |candidate| candidate[:kind] == "query" }

        assert_equal query.hashed_sql, item[:hashed_sql]
        assert_equal "SELECT users", item[:label]
        assert_equal "SELECT * FROM users WHERE id = ?", item[:sql_shape]
        assert_equal [ "app/models/user.rb:12", "app/controllers/users_controller.rb:8" ], item[:call_sites]
        assert_empty item.keys & %i[normalized_sql id query_id tags]
      end

      test "call sites outside the application are not sent" do
        query = rails_pulse_queries(:simple_query)
        summary("RailsPulse::Query", query.id, count: 2)
        operation(query, "/home/deploy/.gems/activerecord/relation.rb", times: 5)
        operation(query, "app/models/user.rb:12", times: 1)

        assert_equal [ "app/models/user.rb:12" ], items.find { |item| item[:kind] == "query" }[:call_sites]
      end

      test "queries past the limit are combined under *" do
        summary("RailsPulse::Query", rails_pulse_queries(:simple_query).id, count: 100, avg: 10.0)
        summary("RailsPulse::Query", rails_pulse_queries(:complex_query).id, count: 2, avg: 1.0)
        query_items = items(limits: { query: 1 }).select { |item| item[:kind] == "query" }

        assert_equal [ rails_pulse_queries(:simple_query).hashed_sql, "*" ], query_items.map { |item| item[:hashed_sql] }
        assert_nil query_items.last[:sql_shape]
        assert_empty query_items.last[:call_sites]
      end

      test "a job is named by its class and queue, with its failures" do
        job = rails_pulse_jobs(:mailer_job)
        summary("RailsPulse::Job", job.id, count: 5, error_count: 1, success_count: 4)
        item = items.find { |candidate| candidate[:kind] == "job" }

        assert_equal [ "UserMailerJob", "mailers", 5, 1, 4 ], item.values_at(:name, :queue_name, :count, :error_count, :success_count)
        assert_not item.key?(:status_2xx)
      end

      test "exception counts are sent per group by fingerprint and overall" do
        group = rails_pulse_exception_groups(:record_not_found)
        summary("RailsPulse::ExceptionGroup", group.id, count: 3)
        summary("RailsPulse::ExceptionGroup", 0, count: 4)

        assert_includes items, { type: "summary", kind: "exception_group", period_start: @hour.utc.iso8601, fingerprint: group.fingerprint, count: 3 }
        assert_includes items, { type: "summary", kind: "exceptions", period_start: @hour.utc.iso8601, count: 4 }
      end

      # Edge Cases

      test "an idle hour still sends its requests item with a count of zero" do
        Summary.delete_all
        summary("RailsPulse::Request", 0, count: 0, avg: nil)

        assert_equal [ [ "requests", 0 ] ], items.map { |item| item.values_at(:kind, :count) }
      end

      test "a summary whose route, query or job has been deleted is skipped" do
        summary("RailsPulse::Route", 999_999, count: 2)
        summary("RailsPulse::Query", 999_999, count: 2)
        summary("RailsPulse::Job", 999_999, count: 2)

        assert_equal [ "requests" ], items.map { |item| item[:kind] }
      end

      private

      def items(route_patterns: @no_patterns, limits: {})
        SummaryItems.new(@hour, adapter: "sqlite3", route_patterns: route_patterns, limits: limits).items
      end

      def summary(type, id, count:, avg: 10.0, **extra)
        Summary.create!(
          summarizable_type: type, summarizable_id: id, period_type: "hour", period_start: @hour, period_end: @hour + 1.hour,
          count: count, avg_duration: avg, min_duration: avg, max_duration: avg, total_duration: avg && (avg * count),
          p50_duration: avg, p95_duration: avg, p99_duration: avg, **extra
        )
      end

      def operation(query, location, times:)
        times.times do
          Operation.create!(request: rails_pulse_requests(:users_request_1), query: query, operation_type: "sql", label: query.normalized_sql,
                            duration: 1.0, occurred_at: @hour + 5.minutes, codebase_location: location)
        end
      end
    end
  end
end
