require "test_helper"
require "rails_pulse/mcp/server"

module RailsPulse
  module Mcp
    class ToolsTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      # Stub client that returns canned API responses and remembers what
      # each tool asked for.
      class StubClient
        attr_reader :calls

        def initialize(responses = {})
          @responses = responses
          @calls = []
        end

        def get(path, params = {})
          @calls << [ path, params ]
          @responses[path] || { "data" => [], "meta" => { "total" => 0, "limit" => 25, "offset" => 0 } }
        end
      end

      REQUESTS_RESPONSE = {
        "data" => [
          {
            "id" => 1, "status" => 200, "duration" => 150.5,
            "controller_action" => "HomeController#index",
            "is_error" => false, "occurred_at" => "2026-06-01T12:00:00Z"
          },
          {
            "id" => 2, "status" => 200, "duration" => 250.0,
            "controller_action" => "HomeController#index",
            "is_error" => false, "occurred_at" => "2026-06-01T11:00:00Z"
          },
          {
            "id" => 3, "status" => 500, "duration" => 300.0,
            "controller_action" => "CheckoutController#create",
            "is_error" => true, "occurred_at" => "2026-06-01T12:30:00Z"
          }
        ],
        "meta" => { "total" => 3, "limit" => 25, "offset" => 0 }
      }.freeze

      # The routes endpoint with a time window: per-route stats, ordered by
      # the requested sort.
      ROUTES_RESPONSE = {
        "data" => [
          {
            "id" => 2, "http_methods" => [ "POST" ], "path" => "/checkout", "controller_action" => "CheckoutController#create",
            "tags" => [], "stats" => { "request_count" => 2, "avg_duration_ms" => 300.0, "error_count" => 1 }
          },
          {
            "id" => 1, "http_methods" => [ "GET" ], "path" => "/", "controller_action" => "HomeController#index",
            "tags" => [], "stats" => { "request_count" => 40, "avg_duration_ms" => 200.0, "error_count" => 0 }
          }
        ],
        "meta" => { "total" => 2, "limit" => 10, "offset" => 0 }
      }.freeze

      def server_context(responses = {})
        { client: StubClient.new(responses) }
      end

      # --- Time windows ---

      # Explicit bounds are what make a before/after-deploy comparison
      # repeatable, so they must reach the API rather than be reduced to a
      # relative period on the way.
      test "a tool forwards explicit bounds to the API" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        Tools::Routes.call(since: "2026-09-24T12:00:00Z", until: "2026-09-25T12:00:00Z", server_context: ctx)

        _path, params = ctx[:client].calls.first

        assert_equal "2026-09-24T12:00:00Z", params[:since]
        assert_equal "2026-09-25T12:00:00Z", params[:until]
      end

      test "a tool omits until when the window runs to now" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        Tools::Routes.call(period: "last_hour", server_context: ctx)

        _path, params = ctx[:client].calls.first

        refute_includes params.keys, :until
      end

      test "a tool echoes the window it measured" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        result = Tools::Routes.call(since: "2026-09-24T12:00:00Z", until: "2026-09-25T12:00:00Z", server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_equal "2026-09-24T12:00:00Z", data["window"]["since"]
        assert_equal "2026-09-25T12:00:00Z", data["window"]["until"]
        assert_equal "custom", data["window"]["period"]
      end

      test "a tool resolves a relative period to a concrete start" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        result = Tools::Routes.call(period: "last_hour", server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_in_delta Time.now - 3600, Time.iso8601(data["window"]["since"]), 5
        assert_equal "last_hour", data["window"]["period"]
      end

      test "a tool reports an unusable timestamp instead of querying" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        result = Tools::Routes.call(since: "the day before the deploy", server_context: ctx)

        assert_predicate result, :error?
        assert_includes result.content.first[:text], "Invalid since"
        assert_empty ctx[:client].calls
      end

      # --- SlowRequests ---

      test "slow_requests asks the routes endpoint for the window sorted by average duration" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        Tools::SlowRequests.call(period: "last_hour", limit: 5, server_context: ctx)

        path, params = ctx[:client].calls.first

        assert_equal "/routes", path
        assert_equal "avg_duration", params[:sort]
        assert_equal 5, params[:limit]
        assert_operator Time.parse(params[:since]), :>, 2.hours.ago
      end

      test "slow_requests returns endpoints in the order the API ranked them" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        result = Tools::SlowRequests.call(server_context: ctx)

        assert_not result.error?
        data = JSON.parse(result.content.first[:text])

        assert_equal 2, data["endpoints"].size
        assert_equal "CheckoutController#create", data["endpoints"].first["endpoint"]
        assert_equal "/checkout", data["endpoints"].first["path"]
        assert_in_delta(300.0, data["endpoints"].first["avg_duration_ms"])
        assert_equal 2, data["routes_with_traffic"]
      end

      test "slow_requests calculates error rate per endpoint" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        result = Tools::SlowRequests.call(server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        checkout = data["endpoints"].find { |e| e["endpoint"] == "CheckoutController#create" }

        assert_in_delta(50.0, checkout["error_rate"])
        assert_equal 1, checkout["error_count"]
      end

      # The threshold is applied by the API before its LIMIT. Filtering the
      # returned page instead hides a qualifying endpoint that ranked below
      # the limit, and reports nothing while an answer exists.
      test "slow_requests forwards min_requests to the routes endpoint" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        Tools::SlowRequests.call(min_requests: 10, server_context: ctx)

        _path, params = ctx[:client].calls.first

        assert_equal 10, params[:min_requests]
      end

      test "slow_requests keeps every endpoint the API returned" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        result = Tools::SlowRequests.call(min_requests: 10, server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_equal [ "CheckoutController#create", "HomeController#index" ], data["endpoints"].map { |e| e["endpoint"] }
      end

      test "slow_requests separates no traffic from nothing meeting min_requests" do
        qualifying_none = {
          "data" => [],
          "meta" => { "total" => 0, "limit" => 10, "offset" => 0, "min_requests" => 10, "routes_with_traffic" => 4 }
        }
        ctx = server_context("/routes" => qualifying_none)
        result = Tools::SlowRequests.call(min_requests: 10, server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_equal 4, data["routes_with_traffic"]
        assert_includes data["summary"], "4 endpoints received traffic"
        assert_includes data["summary"], "min_requests of 10"
        assert_includes data["next_steps"].first, "Lower min_requests below 10"
      end

      test "slow_requests reports no data when nothing was recorded" do
        empty = { "data" => [], "meta" => { "total" => 0, "limit" => 10, "offset" => 0 } }
        ctx = server_context("/routes" => empty)
        result = Tools::SlowRequests.call(server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_equal "No request data found for this period.", data["summary"]
        assert_includes data["next_steps"].first, "Widen the period"
      end

      test "slow_requests includes a summary" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        result = Tools::SlowRequests.call(server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_includes data["summary"], "Slowest endpoint: CheckoutController#create"
        assert_includes data["summary"], "Highest error rate"
      end

      test "slow_requests handles empty data" do
        ctx = server_context
        result = Tools::SlowRequests.call(server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_equal 0, data["endpoints"].size
        assert_includes data["summary"], "No request data"
        assert_includes data["next_steps"].first, "Widen the period"
      end

      test "slow_requests clamps limit" do
        ctx = server_context("/routes" => ROUTES_RESPONSE)
        result = Tools::SlowRequests.call(limit: 999, server_context: ctx)

        assert_not result.error?
        assert_equal 100, ctx[:client].calls.first.last[:limit]
      end

      test "slow_requests handles API error" do
        error_client = Object.new
        def error_client.get(*, **)
          raise CLI::Client::ApiError, "401 Unauthorized"
        end
        ctx = { client: error_client }
        result = Tools::SlowRequests.call(server_context: ctx)

        assert_predicate result, :error?
        assert_includes result.content.first[:text], "401 Unauthorized"
      end

      # --- Errors ---

      test "errors returns error requests grouped by endpoint" do
        ctx = server_context("/requests" => REQUESTS_RESPONSE)
        result = Tools::Errors.call(server_context: ctx)

        assert_not result.error?
        data = JSON.parse(result.content.first[:text])

        assert_equal "5xx", data["status_filter"]
        assert_kind_of Array, data["by_endpoint"]
      end

      test "errors includes total error count" do
        ctx = server_context("/requests" => REQUESTS_RESPONSE)
        result = Tools::Errors.call(server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_equal 3, data["total_errors"]
      end

      test "errors includes summary" do
        error_response = {
          "data" => [
            {
              "id" => 3, "status" => 500, "duration" => 300.0,
              "controller_action" => "CheckoutController#create",
              "is_error" => true, "occurred_at" => "2026-06-01T12:30:00Z"
            }
          ],
          "meta" => { "total" => 1, "limit" => 25, "offset" => 0 }
        }
        ctx = server_context("/requests" => error_response)
        result = Tools::Errors.call(server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_includes data["summary"], "1 total 5xx errors"
      end

      test "errors handles no errors" do
        empty = { "data" => [], "meta" => { "total" => 0, "limit" => 25, "offset" => 0 } }
        ctx = server_context("/requests" => empty)
        result = Tools::Errors.call(server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_includes data["summary"], "No 5xx errors found"
      end

      # --- Exceptions ---

      EXCEPTIONS_RESPONSE = {
        "data" => [
          {
            "id" => 1, "fingerprint" => "abc", "exception_class" => "ActiveRecord::RecordNotFound",
            "location" => "app/models/post.rb#find", "message" => "Couldn't find Post with 'id'=999",
            "status" => "open", "occurrence_count" => 5, "first_seen_at" => "2026-06-01T10:00:00Z",
            "last_seen_at" => "2026-06-01T12:00:00Z", "resolved_at" => nil, "preserve" => false
          },
          {
            "id" => 2, "fingerprint" => "def", "exception_class" => "ZeroDivisionError",
            "location" => "app/services/calculator.rb#divide", "message" => "divided by 0",
            "status" => "open", "occurrence_count" => 1, "first_seen_at" => "2026-06-01T12:30:00Z",
            "last_seen_at" => "2026-06-01T12:30:00Z", "resolved_at" => nil, "preserve" => false
          }
        ],
        "meta" => { "total" => 2, "limit" => 25, "offset" => 0 }
      }.freeze

      test "exceptions asks for open groups in the period by default" do
        ctx = server_context("/exceptions" => EXCEPTIONS_RESPONSE)
        Tools::Exceptions.call(server_context: ctx)
        path, params = ctx[:client].calls.first

        assert_equal "/exceptions", path
        assert_equal "open", params[:status]
        assert_predicate params[:since], :present?
        assert_nil params[:search]
      end

      test "exceptions drops the status and time filters for 'all'" do
        ctx = server_context("/exceptions" => EXCEPTIONS_RESPONSE)
        Tools::Exceptions.call(period: "all", status: "all", search: "post", server_context: ctx)
        _path, params = ctx[:client].calls.first

        assert_nil params[:status]
        assert_nil params[:since]
        assert_equal "post", params[:search]
      end

      test "exceptions returns the groups with a summary and next steps" do
        ctx = server_context("/exceptions" => EXCEPTIONS_RESPONSE)
        result = Tools::Exceptions.call(server_context: ctx)

        assert_not result.error?
        data = JSON.parse(result.content.first[:text])

        assert_equal 2, data["total_groups"]
        assert_equal %w[ActiveRecord::RecordNotFound ZeroDivisionError], data["groups"].map { |g| g["exception_class"] }
        assert_includes data["summary"], "2 open exception group(s)"
        assert_includes data["summary"], "Most frequent: ActiveRecord::RecordNotFound"
        assert_includes data["next_steps"].first, "ZeroDivisionError"
      end

      test "exceptions clamps limit" do
        ctx = server_context("/exceptions" => EXCEPTIONS_RESPONSE)
        Tools::Exceptions.call(limit: 1000, server_context: ctx)
        _path, params = ctx[:client].calls.first

        assert_equal 100, params[:limit]
      end

      test "exceptions handles no groups" do
        empty = { "data" => [], "meta" => { "total" => 0, "limit" => 25, "offset" => 0 } }
        ctx = server_context("/exceptions" => empty)
        data = JSON.parse(Tools::Exceptions.call(server_context: ctx).content.first[:text])

        assert_includes data["summary"], "No open exception groups found"
      end

      # --- Exception (detail) ---

      EXCEPTION_DETAIL_RESPONSE = {
        "data" => {
          "id" => 1, "exception_class" => "ActiveRecord::RecordNotFound", "location" => "app/models/post.rb#find",
          "message" => "Couldn't find Post with 'id'=999", "status" => "open", "occurrence_count" => 5,
          "first_seen_at" => "2026-06-01T10:00:00Z", "last_seen_at" => "2026-06-01T12:00:00Z", "resolved_at" => nil,
          "occurrences" => [
            { "id" => 11, "occurred_at" => "2026-06-01T12:00:00Z", "message" => "Couldn't find Post with 'id'=999",
              "request_method" => "GET", "request_url" => "/posts/999", "request_params" => { "id" => "999" },
              "environment" => "production", "deploy_sha" => "abc1234",
              "backtrace" => [ { "file" => "gems/activerecord/core.rb", "line" => 1, "method" => "find" },
                               { "file" => "app/controllers/posts_controller.rb", "line" => 42, "method" => "show" } ] }
          ]
        }
      }.freeze

      test "exception fetches one group by id with the requested occurrence count" do
        ctx = server_context("/exceptions/1" => EXCEPTION_DETAIL_RESPONSE)
        Tools::ExceptionDetail.call(id: 1, occurrences: 50, server_context: ctx)
        path, params = ctx[:client].calls.first

        assert_equal "/exceptions/1", path
        assert_equal 20, params[:occurrences]
      end

      test "exception returns backtraces, app frames, a summary and next steps" do
        ctx = server_context("/exceptions/1" => EXCEPTION_DETAIL_RESPONSE)
        result = Tools::ExceptionDetail.call(id: 1, server_context: ctx)

        assert_not result.error?
        data = JSON.parse(result.content.first[:text])

        assert_equal "ActiveRecord::RecordNotFound", data["exception_class"]
        assert_equal [ { "location" => "app/controllers/posts_controller.rb:42", "method" => "show" } ], data["app_frames"]
        assert_equal "GET /posts/999", data["occurrences"].first["request"]
        assert_equal 2, data["occurrences"].first["backtrace"].size
        assert_includes data["summary"], "First app frame: app/controllers/posts_controller.rb:42 in show"
        assert_includes data["next_steps"].first, "posts_controller.rb:42"
      end

      test "exception relays an API 404 as a tool error" do
        client = StubClient.new
        client.define_singleton_method(:get) { |*_| raise RailsPulse::CLI::Client::ApiError, "404 Not Found: No exception group with id 9" }
        result = Tools::ExceptionDetail.call(id: 9, server_context: { client: client })

        assert_predicate result, :error?
        assert_includes result.content.first[:text], "No exception group with id 9"
      end

      # --- Endpoint ---

      test "endpoint asks the requests endpoint for that route only" do
        ctx = server_context("/requests" => REQUESTS_RESPONSE)
        Tools::Endpoint.call(endpoint: "/checkout", period: "last_hour", limit: 50, server_context: ctx)

        path, params = ctx[:client].calls.first

        assert_equal "/requests", path
        assert_equal "/checkout", params[:route]
        assert_equal 50, params[:limit]
        assert_operator Time.parse(params[:since]), :>, 2.hours.ago
      end

      test "endpoint returns a profile of the requests the API matched" do
        home_only = { "data" => REQUESTS_RESPONSE["data"].first(2), "meta" => { "total" => 120, "limit" => 200, "offset" => 0 } }
        ctx = server_context("/requests" => home_only)
        result = Tools::Endpoint.call(endpoint: "HomeController#index", server_context: ctx)

        assert_not result.error?
        data = JSON.parse(result.content.first[:text])

        assert_equal "HomeController#index", data["endpoint"]
        assert_equal 120, data["request_count"]
        assert_equal 2, data["sampled_requests"]
        assert_operator data["latency"]["avg_ms"], :>, 0
      end

      # Percentiles over a partial sample describe the sample, not the window.
      # An agent comparing two windows has to be able to tell which it got.
      test "endpoint says when percentiles cover only part of the window" do
        home_only = { "data" => REQUESTS_RESPONSE["data"].first(2), "meta" => { "total" => 120, "limit" => 200, "offset" => 0 } }
        ctx = server_context("/requests" => home_only)
        result = Tools::Endpoint.call(endpoint: "HomeController#index", server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_includes data["latency"]["computed_over"], "2 most recent"
        assert_includes data["latency"]["computed_over"], "120"
        assert_includes data["next_steps"].join, "since/until"
      end

      test "endpoint omits the sampling note when the window is fully covered" do
        complete = { "data" => REQUESTS_RESPONSE["data"].first(2), "meta" => { "total" => 2, "limit" => 200, "offset" => 0 } }
        ctx = server_context("/requests" => complete)
        result = Tools::Endpoint.call(endpoint: "HomeController#index", server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        refute_includes data["latency"].keys, "computed_over"
      end

      test "endpoint includes latency percentiles" do
        ctx = server_context("/requests" => REQUESTS_RESPONSE)
        result = Tools::Endpoint.call(endpoint: "HomeController#index", server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        latency = data["latency"]

        assert latency.key?("avg_ms")
        assert latency.key?("p50_ms")
        assert latency.key?("p95_ms")
        assert latency.key?("p99_ms")
        assert latency.key?("min_ms")
        assert latency.key?("max_ms")
      end

      test "endpoint includes error information" do
        checkout_only = { "data" => REQUESTS_RESPONSE["data"].last(1), "meta" => { "total" => 1 } }
        ctx = server_context("/requests" => checkout_only)
        result = Tools::Endpoint.call(endpoint: "CheckoutController#create", server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_equal 1, data["errors"]["count"]
        assert_in_delta(100.0, data["errors"]["rate"])
        assert_kind_of Array, data["recent_errors"]
      end

      test "endpoint includes next_steps" do
        ctx = server_context("/requests" => REQUESTS_RESPONSE)
        result = Tools::Endpoint.call(endpoint: "HomeController#index", server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_kind_of Array, data["next_steps"]
        assert data["next_steps"].any? { |s| s.include?("source code") }
      end

      test "endpoint next_steps flag high p95 latency and p95/avg ratio" do
        slow = {
          "data" => [ 100.0, 100.0, 100.0, 5000.0 ].each_with_index.map do |duration, i|
            { "id" => i, "status" => 200, "duration" => duration, "controller_action" => "ReportsController#show",
              "is_error" => false, "occurred_at" => "2026-06-01T1#{i}:00:00Z" }
          end,
          "meta" => { "total" => 4 }
        }
        ctx = server_context("/requests" => slow)
        result = Tools::Endpoint.call(endpoint: "ReportsController#show", server_context: ctx)
        steps = JSON.parse(result.content.first[:text])["next_steps"].join("\n")

        assert_includes steps, "P95 latency is over 1s"
        assert_includes steps, "High p95/avg ratio"
      end

      test "endpoint returns helpful message for no match" do
        ctx = server_context
        result = Tools::Endpoint.call(endpoint: "NonexistentController#action", server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_includes data["error"], "No requests found"
      end

      test "endpoint includes summary" do
        home_only = { "data" => REQUESTS_RESPONSE["data"].first(2), "meta" => { "total" => 2 } }
        ctx = server_context("/requests" => home_only)
        result = Tools::Endpoint.call(endpoint: "HomeController#index", server_context: ctx)
        data = JSON.parse(result.content.first[:text])

        assert_includes data["summary"], "2 requests (2 most recent analyzed)"
      end
    end
  end
end
