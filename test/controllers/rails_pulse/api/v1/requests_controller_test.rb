require "test_helper"

module RailsPulse
  module Api
    module V1
      class RequestsControllerTest < ActionDispatch::IntegrationTest
        VALID_TOKEN = "test-api-token"

        setup do
          RailsPulse.configuration.api_token = VALID_TOKEN
        end

        teardown do
          RailsPulse.configuration.api_token = nil
        end

        test "returns 401 without token" do
          get rails_pulse.api_v1_requests_path

          assert_response :unauthorized
        end

        test "returns 401 with wrong token" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => "wrong" }

          assert_response :unauthorized
        end

        test "returns 200 with correct token" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }

          assert_response :success
        end

        test "returns expected JSON shape" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert body.key?("data")
          assert body.key?("meta")
        end

        test "serializes request fields" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)
          req = body["data"].first

          %w[id route_id occurred_at duration status is_error request_uuid controller_action response_size_bytes].each do |k|
            assert_includes req.keys, k
          end
        end

        test "meta total reflects all request records" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert_equal RailsPulse::Request.count, body["meta"]["total"]
        end

        test "filters by exact status code" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { status: 500 }
          body = JSON.parse(response.body)

          assert_equal 2, body["data"].length
          assert_equal [ 500, 500 ], body["data"].map { |r| r["status"] }
        end

        test "filters by 5xx status class" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { status: "5xx" }
          body = JSON.parse(response.body)

          assert_equal 2, body["data"].length
          body["data"].each { |r| assert r["status"] >= 500 && r["status"] < 600 }
        end

        test "filters by 2xx status class" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { status: "2xx" }
          body = JSON.parse(response.body)

          refute_empty body["data"]
          body["data"].each { |r| assert r["status"] >= 200 && r["status"] < 300 }
        end

        test "filters by since time" do
          cutoff = 100.minutes.ago.iso8601
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { since: cutoff }
          body = JSON.parse(response.body)

          body["data"].each { |r| assert_operator Time.parse(r["occurred_at"]), :>=, 100.minutes.ago }
        end

        test "filters by until time" do
          cutoff = 100.minutes.ago.iso8601
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { until: cutoff }
          body = JSON.parse(response.body)

          body["data"].each { |r| assert_operator Time.parse(r["occurred_at"]), :<=, 100.minutes.ago }
        end

        test "route filters by controller action substring, case-insensitively" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { route: "userscontroller#show" }
          body = JSON.parse(response.body)

          refute_empty body["data"]
          body["data"].each { |r| assert_equal "UsersController#show", r["controller_action"] }
          assert_equal body["data"].length, body["meta"]["total"]
        end

        test "route filters by the route's path" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { route: "/api/users" }
          body = JSON.parse(response.body)

          expected = RailsPulse::Request.joins(:route).where(rails_pulse_routes: { path: "/api/users" }).count

          assert_operator expected, :>, 0
          assert_equal expected, body["meta"]["total"]
          assert_equal [ rails_pulse_routes(:api_users).id ], body["data"].map { |r| r["route_id"] }.uniq
        end

        test "route with no match returns an empty page" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { route: "NoSuchController" }
          body = JSON.parse(response.body)

          assert_empty body["data"]
          assert_equal 0, body["meta"]["total"]
        end

        # The route filter escapes LIKE metacharacters and pairs the pattern
        # with an explicit ESCAPE clause. Without it SQLite treats `_` as a
        # wildcard and an endpoint named for one matches nothing.
        test "route matches an underscore literally" do
          underscored = RailsPulse::Route.create!(http_methods: '["PATCH"]', path: "/evaluation/work_orders", controller_action: "evaluation/work_orders#update")
          decoyed = RailsPulse::Route.create!(http_methods: '["PATCH"]', path: "/evaluation/workXorders", controller_action: "evaluation/workXorders#update")
          [ underscored, decoyed ].each_with_index do |route, index|
            RailsPulse::Request.create!(route: route, duration: 10.0, status: 200, is_error: false,
              request_uuid: "like-escape-#{index}", controller_action: route.controller_action, occurred_at: 1.hour.ago)
          end

          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { route: "work_orders" }
          body = JSON.parse(response.body)

          assert_equal 1, body["meta"]["total"]
          assert_equal [ underscored.id ], body["data"].map { |r| r["route_id"] }
        end

        test "route matches a percent sign literally" do
          route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/reports/100%", controller_action: "reports#full")
          RailsPulse::Request.create!(route: route, duration: 10.0, status: 200, is_error: false,
            request_uuid: "like-escape-percent", controller_action: route.controller_action, occurred_at: 1.hour.ago)

          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { route: "100%" }
          body = JSON.parse(response.body)

          assert_equal 1, body["meta"]["total"]
          assert_equal [ route.id ], body["data"].map { |r| r["route_id"] }
        end

        test "returns 400 for a status that is neither a code nor a class" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { status: "failed" }

          assert_response :bad_request
          assert_match(/Invalid status/, JSON.parse(response.body)["error"])
        end

        test "returns 400 when since is not a string" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { since: [ "2026-01-01" ] }

          assert_response :bad_request
          assert_equal "'since' must be a single value", JSON.parse(response.body)["error"]
        end

        test "returns 400 for invalid since time" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { since: "not-a-date" }

          assert_response :bad_request
          assert_includes JSON.parse(response.body)["error"], "Invalid time format for 'since'"
        end

        test "returns 400 for invalid until time" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { until: "not-a-date" }

          assert_response :bad_request
          assert_includes JSON.parse(response.body)["error"], "Invalid time format for 'until'"
        end

        # Parameter Validation
        #
        # Shared by every endpoint through BaseController; exercised here.

        test "reads a time with no zone as UTC" do
          RailsPulse::Request.update_all(occurred_at: Time.utc(2026, 9, 24, 11, 30))
          at_noon = RailsPulse::Request.first
          at_noon.update_columns(occurred_at: Time.utc(2026, 9, 24, 12, 30))

          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: { since: "2026-09-24T12:00:00" }

          assert_equal [ at_noon.id ], JSON.parse(response.body)["data"].map { |r| r["id"] }
        end

        test "refuses a time that is not ISO 8601 rather than guessing" do
          %w[10 yesterday 2026-09-24T12:00:00PST].each do |since|
            get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { since: since }

            assert_response :bad_request, "since=#{since} was accepted"
          end
        end

        test "returns 400 when until is not later than since" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: { since: "2026-09-25T00:00:00Z", until: "2026-09-24T00:00:00Z" }

          assert_response :bad_request
          assert_equal "'until' must be later than 'since'", JSON.parse(response.body)["error"]
        end

        test "returns 400 for a repeated or non-numeric paging value" do
          [ { limit: [ 1, 2 ] }, { offset: { a: 1 } }, { limit: "ten" }, { offset: "-5" } ].each do |params|
            get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: params

            assert_response :bad_request, "#{params} was accepted"
          end
        end

        test "an offset past any table returns an empty page rather than an error" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: { offset: "9" * 30 }

          assert_response :success
          assert_empty JSON.parse(response.body)["data"]
        end

        test "accepts a status class in either case" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { status: "5XX" }

          assert_response :success
        end

        test "respects limit parameter" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { limit: 1 }
          body = JSON.parse(response.body)

          assert_equal 1, body["data"].length
        end

        test "respects offset parameter" do
          get rails_pulse.api_v1_requests_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { offset: 1000 }
          body = JSON.parse(response.body)

          assert_empty body["data"]
        end
      end
    end
  end
end
