require "test_helper"

module RailsPulse
  module Api
    module V1
      class QueriesControllerTest < ActionDispatch::IntegrationTest
        VALID_TOKEN = "test-api-token"

        setup do
          RailsPulse.configuration.api_token = VALID_TOKEN
        end

        teardown do
          RailsPulse.configuration.api_token = nil
        end

        test "returns 401 without token" do
          get rails_pulse.api_v1_queries_path

          assert_response :unauthorized
        end

        test "returns 401 with wrong token" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => "wrong" }

          assert_response :unauthorized
        end

        test "returns 200 with correct token" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }

          assert_response :success
        end

        test "returns expected JSON shape" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert body.key?("data")
          assert body.key?("meta")
          assert_equal %w[total limit offset], body["meta"].keys
        end

        test "serializes query fields" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)
          query = body["data"].first

          %w[id normalized_sql hashed_sql analyzed_at issues suggestions].each { |k| assert_includes query.keys, k }
        end

        test "meta total reflects all query records" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert_equal RailsPulse::Query.count, body["meta"]["total"]
        end

        test "respects limit parameter" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { limit: 1 }
          body = JSON.parse(response.body)

          assert_equal 1, body["data"].length
        end

        test "respects offset parameter" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { offset: 1000 }
          body = JSON.parse(response.body)

          assert_empty body["data"]
        end

        test "returns 400 for invalid since time" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { since: "bad" }

          assert_response :bad_request
        end

        test "returns 400 for invalid until time" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { until: "bad" }

          assert_response :bad_request
        end

        test "stats are nil without a time range" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert body["data"].all? { |q| q["stats"].nil? }
        end

        test "returns 400 for invalid sort" do
          get rails_pulse.api_v1_queries_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { sort: "bogus" }

          assert_response :bad_request
        end

        test "time range returns only queries with operations, with stats, sorted by total duration" do
          seed_operations

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 1.day.ago.iso8601, until: Time.current.iso8601 }
          body = JSON.parse(response.body)

          assert_response :success
          assert_equal 2, body["meta"]["total"]
          assert_equal [ @orders.id, @users.id ], body["data"].map { |q| q["id"] }

          orders = body["data"].first["stats"]

          assert_equal 2, orders["executions"]
          assert_in_delta 150.0, orders["avg_duration_ms"]
          assert_in_delta 200.0, orders["max_duration_ms"]
          assert_in_delta 300.0, orders["total_duration_ms"]
          assert_equal 5, orders["max_repetition_count"]
          assert_nil body["data"].last["stats"]["max_repetition_count"]
        end

        test "sort without since defaults to the last 24 hours" do
          seed_operations

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { sort: "executions" }
          body = JSON.parse(response.body)

          assert_equal 2, body["meta"]["total"]
          assert_equal @orders.id, body["data"].first["id"]
        end

        test "sort by avg_duration reorders results and respects limit" do
          seed_operations

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 1.day.ago.iso8601, sort: "avg_duration", limit: 1 }
          body = JSON.parse(response.body)

          assert_equal [ @users.id ], body["data"].map { |q| q["id"] }
          assert_equal 2, body["meta"]["total"]
        end

        # Drilldown
        #
        # Knowing a query is slow is only half an investigation; these let a
        # caller reach the endpoint it ran inside and the line that issued it.

        test "stats name where each query was issued from, most frequent first" do
          seed_operations

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 1.day.ago.iso8601 }
          body = JSON.parse(response.body)
          orders = body["data"].find { |q| q["id"] == @orders.id }

          assert_equal [ { "location" => "app/models/order.rb:12", "count" => 2 } ], orders["stats"]["source_locations"]
        end

        test "source_locations is empty rather than absent when nothing was recorded" do
          seed_operations
          RailsPulse::Operation.update_all(codebase_location: nil)

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 1.day.ago.iso8601 }
          body = JSON.parse(response.body)

          assert_empty body["data"].first["stats"]["source_locations"]
        end

        test "route restricts queries to the SQL issued while serving that endpoint" do
          seed_operations
          other_route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/other", controller_action: "other#index")
          other_request = RailsPulse::Request.create!(route: other_route, duration: 10.0, status: 200, is_error: false,
            request_uuid: "drilldown-other", controller_action: "other#index", occurred_at: 1.hour.ago)
          RailsPulse::Operation.insert_all!([ op(other_request, @users, 50.0, 1.hour.ago) ])

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 1.day.ago.iso8601, route: other_route.id }
          body = JSON.parse(response.body)

          assert_equal [ @users.id ], body["data"].map { |q| q["id"] }
          assert_equal 1, body["meta"]["total"]
          assert_equal 1, body["data"].first["stats"]["executions"]
        end

        # A query shared across the app is issued from many places; filtered to
        # one endpoint, the locations must be that endpoint's call sites or the
        # drilldown points at the wrong file.
        test "route restricts source_locations to the call sites inside that endpoint" do
          seed_operations
          other_route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/other", controller_action: "other#index")
          other_request = RailsPulse::Request.create!(route: other_route, duration: 10.0, status: 200, is_error: false,
            request_uuid: "drilldown-locations", controller_action: "other#index", occurred_at: 1.hour.ago)
          RailsPulse::Operation.insert_all!([
            op(other_request, @users, 50.0, 1.hour.ago, codebase_location: "app/controllers/other_controller.rb:4")
          ])

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 1.day.ago.iso8601, route: other_route.id }
          body = JSON.parse(response.body)

          assert_equal [ { "location" => "app/controllers/other_controller.rb:4", "count" => 1 } ],
                       body["data"].first["stats"]["source_locations"]
        end

        test "route also accepts a controller action rather than an id" do
          seed_operations

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 1.day.ago.iso8601, route: "api/users" }
          body = JSON.parse(response.body)

          assert_equal 2, body["meta"]["total"]
        end

        test "route implies a window so it works without since" do
          seed_operations

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { route: rails_pulse_routes(:api_users).id }
          body = JSON.parse(response.body)

          assert_equal 2, body["meta"]["total"]
          refute_nil body["data"].first["stats"]
        end

        test "route with no match returns an empty page" do
          seed_operations

          get rails_pulse.api_v1_queries_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 1.day.ago.iso8601, route: "NoSuchController" }
          body = JSON.parse(response.body)

          assert_empty body["data"]
          assert_equal 0, body["meta"]["total"]
        end

        private

        def seed_operations
          @users  = rails_pulse_queries(:simple_query)
          @orders = rails_pulse_queries(:analyzed_query)
          request = rails_pulse_requests(:users_request_1)
          now = Time.current
          RailsPulse::Operation.delete_all

          RailsPulse::Operation.insert_all!([
            op(request, @orders, 100.0, now - 2.hours, repetition_count: 5, codebase_location: "app/models/order.rb:12"),
            op(request, @orders, 200.0, now - 1.hour, codebase_location: "app/models/order.rb:12"),
            op(request, @users, 180.0, now - 3.hours, codebase_location: "app/models/user.rb:7"),
            op(request, @users, 999.0, now - 3.days)
          ])
        end

        def op(request, query, duration, occurred_at, repetition_count: nil, codebase_location: nil)
          {
            request_id: request.id, query_id: query.id, operation_type: "sql", label: query.normalized_sql,
            duration: duration, occurred_at: occurred_at, start_time: 0.0, repetition_count: repetition_count,
            codebase_location: codebase_location, created_at: occurred_at, updated_at: occurred_at
          }
        end
      end
    end
  end
end
