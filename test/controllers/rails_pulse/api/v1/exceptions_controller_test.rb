require "test_helper"

module RailsPulse
  module Api
    module V1
      class ExceptionsControllerTest < ActionDispatch::IntegrationTest
        fixtures :rails_pulse_exception_groups, :rails_pulse_exception_occurrences

        VALID_TOKEN = "test-api-token"
        HEADERS = { "X-Rails-Pulse-Token" => VALID_TOKEN }.freeze

        setup do
          RailsPulse.configuration.api_token = VALID_TOKEN
        end

        teardown do
          RailsPulse.configuration.api_token = nil
        end

        test "returns 401 without token" do
          get rails_pulse.api_v1_exceptions_path

          assert_response :unauthorized
        end

        test "lists every group most recently seen first" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS
          body = JSON.parse(response.body)

          assert_response :success
          assert_equal %w[ZeroDivisionError ActiveRecord::RecordNotFound ArgumentError Net::ReadTimeout],
                       body["data"].map { |g| g["exception_class"] }
          assert_equal 4, body["meta"]["total"]
        end

        test "serializes the group's fields" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { search: "RecordNotFound" }
          group = JSON.parse(response.body)["data"].first

          assert_equal "ActiveRecord::RecordNotFound", group["exception_class"]
          assert_equal "app/models/post.rb#find", group["location"]
          assert_equal "Couldn't find Post with 'id'=999", group["message"]
          assert_equal "open", group["status"]
          assert_equal 5, group["occurrence_count"]
          assert_not_nil group["first_seen_at"]
          assert_not_nil group["last_seen_at"]
          assert_nil group["resolved_at"]
          refute group["preserve"]
        end

        test "filters by status" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { status: "open" }
          body = JSON.parse(response.body)

          assert_equal %w[ZeroDivisionError ActiveRecord::RecordNotFound], body["data"].map { |g| g["exception_class"] }
          assert_equal 2, body["meta"]["total"]
        end

        test "returns 400 for an unknown status" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { status: "closed" }

          assert_response :bad_request
          assert_includes JSON.parse(response.body)["error"], "open, resolved, ignored"
        end

        test "searches class and location" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { search: "calculator" }

          assert_equal [ "ZeroDivisionError" ], JSON.parse(response.body)["data"].map { |g| g["exception_class"] }
        end

        test "fingerprint finds one group whatever its status" do
          group = rails_pulse_exception_groups(:resolved_group)

          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { fingerprint: group.fingerprint }
          body = JSON.parse(response.body)

          assert_equal [ group.id ], body["data"].map { |g| g["id"] }
          assert_equal group.fingerprint, body["data"].first["fingerprint"]
        end

        test "fingerprint matches exactly, not as a prefix" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { fingerprint: "abc123" }
          body = JSON.parse(response.body)

          assert_empty body["data"]
          assert_equal 0, body["meta"]["total"]
        end

        test "search matches an underscore literally" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { search: "http_client", status: "ignored" }

          assert_equal [ "Net::ReadTimeout" ], JSON.parse(response.body)["data"].map { |g| g["exception_class"] }
        end

        test "search does not treat a percent sign as a wildcard" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { search: "http%client" }

          assert_empty JSON.parse(response.body)["data"]
        end

        test "sorts by occurrence count" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { sort: "occurrence_count" }

          assert_equal [ 10, 5, 2, 1 ], JSON.parse(response.body)["data"].map { |g| g["occurrence_count"] }
        end

        test "returns 400 for an unknown sort" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { sort: "message" }

          assert_response :bad_request
        end

        test "filters by when the group was last seen" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS,
              params: { since: 3.hours.ago.iso8601, until: 45.minutes.ago.iso8601 }

          assert_equal [ "ActiveRecord::RecordNotFound" ], JSON.parse(response.body)["data"].map { |g| g["exception_class"] }
        end

        test "returns 400 for invalid since" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { since: "yesterday-ish" }

          assert_response :bad_request
        end

        test "respects limit and offset" do
          get rails_pulse.api_v1_exceptions_path, headers: HEADERS, params: { limit: 1, offset: 1 }
          body = JSON.parse(response.body)

          assert_equal [ "ActiveRecord::RecordNotFound" ], body["data"].map { |g| g["exception_class"] }
          assert_equal 4, body["meta"]["total"]
        end

        test "show returns the group with its most recent occurrences first" do
          group = rails_pulse_exception_groups(:record_not_found)

          get rails_pulse.api_v1_exception_path(group), headers: HEADERS
          body = JSON.parse(response.body)["data"]

          assert_response :success
          assert_equal "ActiveRecord::RecordNotFound", body["exception_class"]
          assert_equal 2, body["occurrences"].size
          latest = body["occurrences"].first

          assert_equal "Couldn't find Post with 'id'=999", latest["message"]
          assert_equal "GET", latest["request_method"]
          assert_equal "/posts/999", latest["request_url"]
          assert_equal({ "id" => "999", "controller" => "posts", "action" => "show" }, latest["request_params"])
          assert_equal "production", latest["environment"]
          assert_equal "abc1234", latest["deploy_sha"]
          assert_equal [ { "file" => "app/controllers/posts_controller.rb", "line" => 42, "method" => "show" },
                         { "file" => "app/models/post.rb", "line" => 10, "method" => "find" } ], latest["backtrace"]
          assert_nil body["occurrences"].last["request_params"]
        end

        test "show limits occurrences and clamps the count" do
          group = rails_pulse_exception_groups(:record_not_found)

          get rails_pulse.api_v1_exception_path(group), headers: HEADERS, params: { occurrences: 1 }

          assert_equal 1, JSON.parse(response.body)["data"]["occurrences"].size

          get rails_pulse.api_v1_exception_path(group), headers: HEADERS, params: { occurrences: 0 }

          assert_equal 1, JSON.parse(response.body)["data"]["occurrences"].size
        end

        test "show returns 404 for an unknown group" do
          get rails_pulse.api_v1_exception_path(id: 999_999), headers: HEADERS

          assert_response :not_found
          assert_includes JSON.parse(response.body)["error"], "999999"
        end

        test "show returns 401 without token" do
          get rails_pulse.api_v1_exception_path(rails_pulse_exception_groups(:record_not_found))

          assert_response :unauthorized
        end

        test "returns empty data when there are no groups" do
          RailsPulse::ExceptionOccurrence.delete_all
          RailsPulse::ExceptionGroup.delete_all

          get rails_pulse.api_v1_exceptions_path, headers: HEADERS
          body = JSON.parse(response.body)

          assert_empty body["data"]
          assert_equal 0, body["meta"]["total"]
        end
      end
    end
  end
end
