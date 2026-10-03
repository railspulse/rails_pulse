require "test_helper"

module RailsPulse
  class ConfigRecommendationsTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_queries

    # Default route thresholds: slow 500, very_slow 1500, critical 3000.
    # Default query thresholds: slow 100, very_slow 500, critical 1000.

    # Structure Tests

    test "a recommendation has a title, detail and config snippet" do
      rec = recommendations(route_rows: rows(600, 700, 800, 100, 100)).first

      assert_equal "Route slow threshold may be too low", rec[:title]
      assert_includes rec[:detail], "3 of 5 sampled routes exceeded the 500ms slow threshold"
      assert_equal "config.route_thresholds = { slow: 750, very_slow: 1500, critical: 3000 }", rec[:config_snippet]
    end

    # Calculation Tests

    test "recommends raising the route slow threshold when 40% of routes exceed it" do
      # 500 * 1.5 = 750, already a multiple of 50
      recs = recommendations(route_rows: rows(600, 700, 800, 100, 100))

      assert_includes titles(recs), "Route slow threshold may be too low"
    end

    test "does not recommend raising the route slow threshold when under 40% exceed it" do
      recs = recommendations(route_rows: rows(600, 600, 100, 100, 100, 100, 100, 100))

      assert_not_includes titles(recs), "Route slow threshold may be too low"
    end

    test "recommends lowering the route critical threshold when nothing came within half of it" do
      # max(ceil_to(1000 * 2, 500), 500 * 3, very_slow 1500) = 2000
      rec = recommendations(route_rows: rows(1000, 900, 800)).find { |r| r[:title] == "Route critical threshold may be too permissive" }

      assert_equal "config.route_thresholds = { slow: 500, very_slow: 1500, critical: 2000 }", rec[:config_snippet]
      assert_includes rec[:detail], "highest P95: 1000ms"
    end

    test "a lowered critical threshold is never below very_slow" do
      # ceil_to(200 * 2, 500) = 500 and 500 * 3 = 1500; very_slow 2500 wins
      with_route_thresholds(slow: 500, very_slow: 2500, critical: 5000) do
        rec = recommendations(route_rows: rows(200, 150, 100)).find { |r| r[:title].include?("critical") }

        assert_equal "config.route_thresholds = { slow: 500, very_slow: 2500, critical: 2500 }", rec[:config_snippet]
      end
    end

    test "returns both route recommendations when both conditions hold" do
      recs = recommendations(route_rows: rows(600, 700, 800, 600, 600))

      assert_equal 2, recs.size
    end

    test "recommends raising the query slow threshold when 40% of queries exceed it" do
      rec = recommendations(query_rows: rows(200, 300, 400, 50, 50)).find { |r| r[:title] == "Query slow threshold may be too low" }

      assert_equal "config.query_thresholds = { slow: 150, very_slow: 500, critical: 1000 }", rec[:config_snippet]
    end

    test "recommends lowering the query critical threshold when nothing came within half of it" do
      # max(ceil_to(400 * 2, 100), 100 * 3, very_slow 500) = 800
      rec = recommendations(query_rows: rows(400, 300, 200)).find { |r| r[:title] == "Query critical threshold may be too permissive" }

      assert_equal "config.query_thresholds = { slow: 100, very_slow: 500, critical: 800 }", rec[:config_snippet]
    end

    test "slow threshold suggestions round up to the step" do
      # 510 * 1.5 = 765, rounded up to 800
      with_route_thresholds(slow: 510, very_slow: 1500, critical: 3000) do
        rec = recommendations(route_rows: rows(600, 700, 800)).find { |r| r[:title].include?("slow") }

        assert_includes rec[:config_snippet], "slow: 800"
      end
    end

    test "for_period samples the period's slowest routes and most expensive queries" do
      RailsPulse::Summary.delete_all
      period_start = Time.zone.parse("2026-06-01")
      %i[api_users api_posts api_test].each { |name| summary(rails_pulse_routes(name), period_start, p95: 900) }
      summary(rails_pulse_routes(:api_other), period_start - 1.week, p95: 9000)

      recs = ConfigRecommendations.for_period(period_type: "week", period_start: period_start).to_recommendations

      assert_includes titles(recs), "Route slow threshold may be too low"
      assert_includes recs.first[:detail], "3 of 3 sampled routes"
    end

    # Edge Cases

    test "returns nothing with fewer than 3 route rows" do
      assert_empty recommendations(route_rows: rows(600, 700))
    end

    test "returns nothing with fewer than 3 query rows" do
      assert_empty recommendations(query_rows: rows(200, 300))
    end

    test "returns nothing when no condition is met" do
      # 1 of 5 exceed slow (20%); max 1600 is past critical / 2
      assert_empty recommendations(route_rows: rows(1600, 100, 100, 100, 100))
    end

    test "rows with no P95 count as zero" do
      assert_empty recommendations(route_rows: [ { p95_duration: nil } ] * 3)
    end

    test "for_period with no summaries recommends nothing" do
      RailsPulse::Summary.delete_all

      assert_empty ConfigRecommendations.for_period(period_type: "week", period_start: Time.zone.parse("2026-06-01")).to_recommendations
    end

    private

    def recommendations(route_rows: [], query_rows: [])
      ConfigRecommendations.new(route_rows: route_rows, query_rows: query_rows).to_recommendations
    end

    def rows(*p95s)
      p95s.map { |p95| { p95_duration: p95 } }
    end

    def titles(recs)
      recs.map { |r| r[:title] }
    end

    def with_route_thresholds(thresholds)
      original = RailsPulse.configuration.route_thresholds
      RailsPulse.configuration.route_thresholds = thresholds
      yield
    ensure
      RailsPulse.configuration.route_thresholds = original
    end

    def summary(record, period_start, p95:)
      RailsPulse::Summary.create!(
        summarizable: record, period_type: "week", period_start: period_start,
        period_end: period_start.end_of_week, count: 100, avg_duration: p95 / 2,
        p95_duration: p95, error_count: 0, success_count: 100
      )
    end
  end
end
