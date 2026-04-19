require "test_helper"

module RailsPulse
  module Dashboard
    module Charts
      class ResponseTimePercentilesTest < ActiveSupport::TestCase
        fixtures :rails_pulse_routes, :rails_pulse_summaries

        def setup
          RailsPulse::Summary.delete_all
          @now = Time.current
          travel_to @now
        end

        def teardown
          travel_back
        end

        # Structure Tests

        test "returns nil when no summaries exist" do
          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new.to_chart_data

          assert_nil result
        end

        test "returns hash with labels and series keys" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new.to_chart_data

          assert_kind_of Hash, result
          assert_includes result.keys, :labels
          assert_includes result.keys, :series
        end

        test "returns three series by default (P50, P95, P99)" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new.to_chart_data

          # Should have at least 3 series (P50, P95, P99), may have more if SLO configured
          assert_operator result[:series].length, :>=, 3
          # Verify the 3 main series exist
          assert result[:series].any? { |s| s[:name] == "P50" }
          assert result[:series].any? { |s| s[:name] == "P95" }
          assert result[:series].any? { |s| s[:name] == "P99" }
        end

        test "first series is named P50 with line type" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new.to_chart_data
          p50_series = result[:series].find { |s| s[:name] == "P50" }

          assert_not_nil p50_series
          assert_equal "line", p50_series[:type]
        end

        test "includes P95 series with line type" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new.to_chart_data
          p95_series = result[:series].find { |s| s[:name] == "P95" }

          assert_not_nil p95_series
          assert_equal "line", p95_series[:type]
        end

        test "includes P99 series with line type" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new.to_chart_data
          p99_series = result[:series].find { |s| s[:name] == "P99" }

          assert_not_nil p99_series
          assert_equal "line", p99_series[:type]
        end

        test "labels count matches period days plus today" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data

          assert_equal 8, result[:labels].length
        end

        # Calculation Tests

        test "returns correct P50 value for a day" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 150, p95: 400, p99: 600, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data
          yesterday_index = result[:labels].index(1.day.ago.to_date.strftime("%b %-d"))
          p50_series = result[:series].find { |s| s[:name] == "P50" }

          assert_equal 150, p50_series[:data][yesterday_index]
        end

        test "returns correct P95 value for a day" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 150, p95: 400, p99: 600, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data
          yesterday_index = result[:labels].index(1.day.ago.to_date.strftime("%b %-d"))
          p95_series = result[:series].find { |s| s[:name] == "P95" }

          assert_equal 400, p95_series[:data][yesterday_index]
        end

        test "returns correct P99 value for a day" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 150, p95: 400, p99: 600, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data
          yesterday_index = result[:labels].index(1.day.ago.to_date.strftime("%b %-d"))
          p99_series = result[:series].find { |s| s[:name] == "P99" }

          assert_equal 600, p99_series[:data][yesterday_index]
        end

        test "fills nil for days with no data" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data
          five_days_ago_index = result[:labels].index(5.days.ago.to_date.strftime("%b %-d"))
          p50_series = result[:series].find { |s| s[:name] == "P50" }

          assert_nil p50_series[:data][five_days_ago_index]
        end

        test "calculates weighted average P50 across multiple routes on same day" do
          # Route A: 100 requests at P50=200ms
          # Route B: 100 requests at P50=400ms
          # Weighted avg = (200*100 + 400*100) / 200 = 300ms
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 200, p95: 500, p99: 700, count: 100)
          create_route_day_summary(rails_pulse_routes(:api_posts), 1.day.ago, p50: 400, p95: 600, p99: 800, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data
          yesterday_index = result[:labels].index(1.day.ago.to_date.strftime("%b %-d"))
          p50_series = result[:series].find { |s| s[:name] == "P50" }

          assert_equal 300, p50_series[:data][yesterday_index]
        end

        test "calculates weighted average P95 across multiple routes with different counts" do
          # Route A: 200 requests at P95=300ms → weighted contribution: 60000
          # Route B: 100 requests at P95=600ms → weighted contribution: 60000
          # Weighted avg = 120000 / 300 = 400ms
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 200)
          create_route_day_summary(rails_pulse_routes(:api_posts), 1.day.ago, p50: 100, p95: 600, p99: 800, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data
          yesterday_index = result[:labels].index(1.day.ago.to_date.strftime("%b %-d"))
          p95_series = result[:series].find { |s| s[:name] == "P95" }

          assert_equal 400, p95_series[:data][yesterday_index]
        end

        test "excludes data outside the period" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)
          create_route_day_summary(rails_pulse_routes(:api_users), 10.days.ago, p50: 999, p95: 999, p99: 999, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data

          assert_equal 8, result[:labels].length
          p50_series = result[:series].find { |s| s[:name] == "P50" }

          refute_includes p50_series[:data], 999
        end

        # SLO Series Tests

        test "omits SLO series when none configured" do
          RailsPulse.configuration.service_level_objectives = []
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new.to_chart_data

          assert_equal 3, result[:series].length
          refute result[:series].any? { |s| s[:name].include?("SLO") }
        end

        test "includes SLO series when configured" do
          RailsPulse.configuration.service_level_objectives = [ { percentile: 95, threshold: 500 } ]
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new.to_chart_data

          slo_series = result[:series].find { |s| s[:name].include?("SLO") }

          assert_not_nil slo_series
        ensure
          RailsPulse.configuration.service_level_objectives = []
        end

        test "SLO series data is a flat line at the threshold value" do
          RailsPulse.configuration.service_level_objectives = [ { percentile: 95, threshold: 500 } ]
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data
          slo_series = result[:series].find { |s| s[:name].include?("SLO") }

          assert_equal 8, slo_series[:data].length
          assert slo_series[:data].all? { |v| v == 500 }
        ensure
          RailsPulse.configuration.service_level_objectives = []
        end

        # Tag Filtering Tests

        test "excludes summaries for routes with disabled tags" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 200, p95: 400, p99: 600, count: 100)
          create_route_day_summary(rails_pulse_routes(:api_cleanup), 1.day.ago, p50: 999, p95: 999, p99: 999, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(
            period: 7,
            disabled_tags: [ "maintenance" ]
          ).to_chart_data

          yesterday_index = result[:labels].index(1.day.ago.to_date.strftime("%b %-d"))
          p50_series = result[:series].find { |s| s[:name] == "P50" }

          assert_equal 200, p50_series[:data][yesterday_index]
        end

        test "excludes non-tagged routes when show_non_tagged is false" do
          create_route_day_summary(rails_pulse_routes(:api_users), 1.day.ago, p50: 200, p95: 400, p99: 600, count: 100)
          create_route_day_summary(rails_pulse_routes(:api_other), 1.day.ago, p50: 999, p95: 999, p99: 999, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(
            period: 7,
            show_non_tagged: false
          ).to_chart_data

          yesterday_index = result[:labels].index(1.day.ago.to_date.strftime("%b %-d"))
          p50_series = result[:series].find { |s| s[:name] == "P50" }

          assert_equal 200, p50_series[:data][yesterday_index]
        end

        test "returns nil when all summaries filtered out by tags" do
          create_route_day_summary(rails_pulse_routes(:api_cleanup), 1.day.ago, p50: 100, p95: 300, p99: 500, count: 50)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(
            period: 7,
            disabled_tags: [ "maintenance" ]
          ).to_chart_data

          assert_nil result
        end

        # Edge Cases

        test "handles nil percentile values gracefully by treating as zero" do
          RailsPulse::Summary.create!(
            summarizable: rails_pulse_routes(:api_users),
            period_start: 1.day.ago.beginning_of_day,
            period_end: 1.day.ago.end_of_day,
            period_type: "day",
            count: 100,
            avg_duration: 150.0,
            p50_duration: nil,
            p95_duration: nil,
            p99_duration: nil
          )

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 7).to_chart_data
          yesterday_index = result[:labels].index(1.day.ago.to_date.strftime("%b %-d"))
          p50_series = result[:series].find { |s| s[:name] == "P50" }

          assert_equal 0, p50_series[:data][yesterday_index]
        end

        test "works with 30-day period" do
          create_route_day_summary(rails_pulse_routes(:api_users), 15.days.ago, p50: 100, p95: 300, p99: 500, count: 100)

          result = RailsPulse::Dashboard::Charts::ResponseTimePercentiles.new(period: 30).to_chart_data

          assert_equal 31, result[:labels].length
          assert_includes result[:labels], 15.days.ago.to_date.strftime("%b %-d")
        end

        private

        def create_route_day_summary(route, date, p50:, p95:, p99:, count:)
          RailsPulse::Summary.create!(
            summarizable: route,
            period_start: date.beginning_of_day,
            period_end: date.end_of_day,
            period_type: "day",
            count: count,
            avg_duration: p50.to_f,
            p50_duration: p50.to_f,
            p95_duration: p95.to_f,
            p99_duration: p99.to_f
          )
        end
      end
    end
  end
end
