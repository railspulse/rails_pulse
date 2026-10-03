require "test_helper"

module RailsPulse
  module Api
    module V1
      class InsightsControllerTest < ActionDispatch::IntegrationTest
        fixtures :rails_pulse_routes, :rails_pulse_queries

        VALID_TOKEN = "test-api-token"
        HEADERS = { "X-Rails-Pulse-Token" => VALID_TOKEN }.freeze

        # Wednesday 17 June; the last complete week began on Monday the 8th.
        FROZEN_NOW = Time.zone.parse("2026-06-17 12:00:00").freeze
        LAST_WEEK  = Time.zone.parse("2026-06-08 00:00:00").freeze

        setup do
          travel_to FROZEN_NOW
          RailsPulse.configuration.api_token = VALID_TOKEN
          RailsPulse::Summary.delete_all
        end

        teardown do
          RailsPulse.configuration.api_token = nil
          travel_back
        end

        # Structure Tests

        test "returns 401 without token" do
          get rails_pulse.api_v1_insights_path

          assert_response :unauthorized
        end

        test "returns the period, thresholds, needs attention and recommendations" do
          body = get_insights

          assert_response :success
          assert_equal %w[period thresholds needs_attention threshold_recommendations], body.keys
          assert_equal({ "slow" => 500, "very_slow" => 1500, "critical" => 3000 }, body["thresholds"]["routes"])
          assert_equal 0, body["needs_attention"]["total"]
        end

        test "defaults to the last complete week" do
          period = get_insights["period"]

          assert_equal "week", period["type"]
          assert_equal LAST_WEEK, Time.zone.parse(period["start"])
          assert_equal LAST_WEEK.end_of_week.to_i, Time.zone.parse(period["end"]).to_i
        end

        test "lists what needs attention in the period with record ids" do
          route = rails_pulse_routes(:api_users)
          summary(route, p95: 3200.0)
          item = get_insights["needs_attention"]["critical"].first

          assert_equal "route", item["type"]
          assert_equal route.id, item["id"]
          assert_equal "critical", item["severity"]
          assert_includes item["reason"], "exceeds 3000ms threshold"
        end

        test "recommends threshold changes from the period's slowest routes" do
          %i[api_users api_posts api_test].each { |name| summary(rails_pulse_routes(name), p95: 700.0) }
          recs = get_insights["threshold_recommendations"]

          assert_includes recs.map { |r| r["title"] }, "Route slow threshold may be too low"
          assert recs.all? { |r| r["config_snippet"].start_with?("config.") }
        end

        test "summarized is true once SummaryJob has written the period's overall row" do
          summary(nil, p95: 100.0)

          assert get_insights["period"]["summarized"]
        end

        test "summarized is false for a period with no overall row" do
          assert_not get_insights["period"]["summarized"]
        end

        # Parameter Tests

        test "period and at select the period containing that time" do
          period = get_insights(period: "day", at: "2026-06-10T15:30:00Z")["period"]

          assert_equal "day", period["type"]
          assert_equal Time.zone.parse("2026-06-10 15:30:00 UTC").beginning_of_day, Time.zone.parse(period["start"])
        end

        test "period without at reads the last complete one" do
          period = get_insights(period: "month")["period"]

          assert_equal Time.zone.parse("2026-05-01 00:00:00"), Time.zone.parse(period["start"])
        end

        test "hour is the last complete hour" do
          period = get_insights(period: "hour")["period"]

          assert_equal Time.zone.parse("2026-06-17 11:00:00"), Time.zone.parse(period["start"])
        end

        # Edge Cases

        test "an unknown period is a 400 naming the accepted values" do
          body = get_insights(period: "year")

          assert_response :bad_request
          assert_includes body["error"], "hour, day, week, month"
        end

        test "an invalid at is a 400" do
          get_insights(at: "last tuesday")

          assert_response :bad_request
        end

        test "a repeated period is a 400" do
          get "#{rails_pulse.api_v1_insights_path}?period[]=week", headers: HEADERS

          assert_response :bad_request
        end

        private

        def get_insights(params = {})
          get rails_pulse.api_v1_insights_path, headers: HEADERS, params: params
          JSON.parse(response.body)
        end

        # A week summary for the record, or the overall request row when nil.
        def summary(record, p95:)
          RailsPulse::Summary.create!(
            summarizable_type: record ? record.class.name : "RailsPulse::Request",
            summarizable_id:   record ? record.id : 0,
            period_type:       "week",
            period_start:      LAST_WEEK,
            period_end:        LAST_WEEK.end_of_week,
            count:             100,
            avg_duration:      p95 / 2,
            p95_duration:      p95,
            error_count:       0,
            success_count:     100
          )
        end
      end
    end
  end
end
