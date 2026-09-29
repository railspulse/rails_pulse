require "test_helper"

module RailsPulse
  module Api
    module V1
      class RoutesControllerTest < ActionDispatch::IntegrationTest
        VALID_TOKEN = "test-api-token"

        setup do
          RailsPulse.configuration.api_token = VALID_TOKEN
        end

        teardown do
          RailsPulse.configuration.api_token = nil
        end

        test "returns 401 without token" do
          get rails_pulse.api_v1_routes_path

          assert_response :unauthorized
          assert_equal "Unauthorized", JSON.parse(response.body)["error"]
        end

        test "returns 401 with wrong token" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => "wrong" }

          assert_response :unauthorized
        end

        # The deployment credential writes releases; it must not also read
        # telemetry, or splitting the two buys nothing.
        test "returns 401 for the deployment token" do
          RailsPulse.configuration.deployment_token = "deploy-token"
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => "deploy-token" }

          assert_response :unauthorized
        ensure
          RailsPulse.configuration.deployment_token = nil
        end

        test "returns 401 when token is unconfigured" do
          RailsPulse.configuration.api_token = nil
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }

          assert_response :unauthorized
        end

        # The schema report names missing tables and columns; the token
        # check must run before it.
        test "returns 401, not the schema report, to an anonymous caller when the schema is outdated" do
          RailsPulse::SchemaCheck.stubs(:current?).returns(false)
          RailsPulse::SchemaCheck.stubs(:missing).returns({ "rails_pulse_events" => [ "table" ] })
          RailsPulse::SchemaCheck.stubs(:warn_once!)

          get rails_pulse.api_v1_routes_path

          assert_response :unauthorized
          assert_equal({ "error" => "Unauthorized" }, JSON.parse(response.body))
        end

        test "returns the JSON schema report to an authenticated caller when the schema is outdated" do
          RailsPulse::SchemaCheck.stubs(:current?).returns(false)
          RailsPulse::SchemaCheck.stubs(:missing).returns({ "rails_pulse_events" => [ "table" ] })
          RailsPulse::SchemaCheck.stubs(:warn_once!)

          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }

          assert_response :service_unavailable
          assert_match(/schema upgrade/, JSON.parse(response.body)["error"])
        end

        test "does not touch the session" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }

          assert_response :success
          assert_nil session[:show_non_tagged]
        end

        test "returns 200 with correct token" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }

          assert_response :success
        end

        test "returns expected JSON shape with data array and meta" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert body.key?("data")
          assert body.key?("meta")
          assert_equal %w[total limit offset], body["meta"].keys
        end

        test "serializes route fields" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)
          route = body["data"].first

          %w[id http_methods path controller_action tags created_at stats].each { |k| assert_includes route.keys, k }
          assert_nil route["stats"]
        end

        test "search filters by path or controller action" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { search: "USERS" }
          body = JSON.parse(response.body)

          assert_equal [ "/api/users" ], body["data"].map { |r| r["path"] }
          assert_equal 1, body["meta"]["total"]
        end

        # min_requests is applied before the LIMIT, so a qualifying route that
        # ranks below the limit is still reachable. Filtering the page after
        # the fact returned nothing here.
        test "min_requests keeps a busy route that ranks below the limit" do
          busy = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/busy", controller_action: "busy#index")
          12.times do |i|
            RailsPulse::Request.create!(route: busy, duration: 5.0, status: 200, is_error: false,
              request_uuid: "min-req-busy-#{i}", controller_action: "busy#index", occurred_at: 1.hour.ago)
          end
          3.times do |i|
            rare = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/rare#{i}", controller_action: "rare#{i}#index")
            RailsPulse::Request.create!(route: rare, duration: 10_000.0, status: 200, is_error: false,
              request_uuid: "min-req-rare-#{i}", controller_action: "rare#{i}#index", occurred_at: 1.hour.ago)
          end

          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: { since: 2.hours.ago.iso8601, sort: "avg_duration", limit: 3, min_requests: 10 }
          body = JSON.parse(response.body)

          assert_equal [ "/busy" ], body["data"].map { |r| r["path"] }
          assert_equal 1, body["meta"]["total"]
        end

        test "min_requests reports how many routes had traffic" do
          route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/quiet", controller_action: "quiet#index")
          RailsPulse::Request.create!(route: route, duration: 5.0, status: 200, is_error: false,
            request_uuid: "min-req-quiet", controller_action: "quiet#index", occurred_at: 1.hour.ago)

          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: { since: 2.hours.ago.iso8601, sort: "avg_duration", min_requests: 1_000_000 }
          body = JSON.parse(response.body)

          assert_empty body["data"]
          assert_equal 0, body["meta"]["total"]
          assert_equal 1_000_000, body["meta"]["min_requests"]
          assert_operator body["meta"]["routes_with_traffic"], :>, 0
        end

        test "min_requests is absent from meta when unset" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: { since: 2.hours.ago.iso8601, sort: "avg_duration" }
          body = JSON.parse(response.body)

          refute_includes body["meta"].keys, "min_requests"
          refute_includes body["meta"].keys, "routes_with_traffic"
        end

        # LIKE metacharacters are escaped and paired with an explicit ESCAPE
        # clause, so a search term containing one matches it literally rather
        # than as a wildcard. SQLite has no default escape character, so
        # without the clause these searches silently return nothing.

        test "search matches an underscore literally" do
          RailsPulse::Route.create!(http_methods: '["PATCH"]', path: "/evaluation/work_orders", controller_action: "evaluation/work_orders#update")
          RailsPulse::Route.create!(http_methods: '["PATCH"]', path: "/evaluation/workXorders", controller_action: "evaluation/workXorders#update")

          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { search: "work_orders" }
          body = JSON.parse(response.body)

          assert_equal [ "/evaluation/work_orders" ], body["data"].map { |r| r["path"] }
        end

        test "search matches a percent sign literally" do
          RailsPulse::Route.create!(http_methods: '["GET"]', path: "/reports/100%", controller_action: "reports#full")

          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { search: "100%" }
          body = JSON.parse(response.body)

          assert_equal [ "/reports/100%" ], body["data"].map { |r| r["path"] }
        end

        test "search matches the escape character literally" do
          RailsPulse::Route.create!(http_methods: '["GET"]', path: "/alerts/urgent!", controller_action: "alerts#urgent")

          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { search: "urgent!" }
          body = JSON.parse(response.body)

          assert_equal [ "/alerts/urgent!" ], body["data"].map { |r| r["path"] }
        end

        test "search matches a backslash literally" do
          RailsPulse::Route.create!(http_methods: '["GET"]', path: "/files/a\\b", controller_action: "files#show")

          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { search: "a\\b" }
          body = JSON.parse(response.body)

          assert_equal [ "/files/a\\b" ], body["data"].map { |r| r["path"] }
        end

        test "returns 400 for invalid sort" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { sort: "bogus" }

          assert_response :bad_request
        end

        test "time range adds request stats ordered by request count" do
          get rails_pulse.api_v1_routes_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 20.hours.ago.iso8601 }
          body = JSON.parse(response.body)

          assert_response :success
          assert_equal [ "/api/users", "/api/posts", "/api/other" ], body["data"].map { |r| r["path"] }
          assert_equal 3, body["meta"]["total"]

          users = body["data"].first

          assert_equal "api/users#index", users["controller_action"]
          assert_equal 5, users["stats"]["request_count"]
          assert_in_delta 1320.1, users["stats"]["avg_duration_ms"]
          assert_equal 1, users["stats"]["error_count"]
          assert_equal 0, body["data"].second["stats"]["error_count"]
        end

        test "sort by error_count without since defaults to the last 24 hours" do
          get rails_pulse.api_v1_routes_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { sort: "error_count" }
          body = JSON.parse(response.body)

          # /api/users and /api/other each had one error in the last 24 hours.
          assert_equal [ "/api/other", "/api/users" ], body["data"].first(2).map { |r| r["path"] }.sort
          assert_equal 1, body["data"].first["stats"]["error_count"]
        end

        test "search combines with stats and pagination" do
          get rails_pulse.api_v1_routes_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 20.hours.ago.iso8601, search: "posts", limit: 1 }
          body = JSON.parse(response.body)

          assert_equal [ "/api/posts" ], body["data"].map { |r| r["path"] }
          assert_equal 1, body["meta"]["total"]
        end

        test "routes without traffic in the window are omitted" do
          get rails_pulse.api_v1_routes_path,
              headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
              params: { since: 10.minutes.ago.iso8601 }
          body = JSON.parse(response.body)

          assert_empty body["data"]
          assert_equal 0, body["meta"]["total"]
        end

        test "meta total reflects all route records" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert_equal RailsPulse::Route.count, body["meta"]["total"]
        end

        test "respects limit parameter" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { limit: 1 }
          body = JSON.parse(response.body)

          assert_equal 1, body["data"].length
          assert_equal 1, body["meta"]["limit"]
        end

        test "respects offset parameter" do
          get rails_pulse.api_v1_routes_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { offset: 1000 }
          body = JSON.parse(response.body)

          assert_empty body["data"]
          assert_equal RailsPulse::Route.count, body["meta"]["total"]
        end
      end
    end
  end
end
