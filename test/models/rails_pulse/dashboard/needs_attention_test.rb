require "test_helper"

module RailsPulse
  module Dashboard
    class NeedsAttentionTest < ActiveSupport::TestCase
      fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_jobs

      def setup
        RailsPulse::Summary.delete_all
        # Findings are loaded globally by `fixtures :all`; clear them so a test
        # only sees the regressions it creates itself.
        RailsPulse::Finding.delete_all
        # Zero out all jobs so they don't appear in results unless the test creates them
        RailsPulse::Job.update_all(runs_count: 0, failures_count: 0, p95_duration: nil)
        # Neutralize the query_with_issues fixture so it doesn't pollute unrelated tests
        rails_pulse_queries(:query_with_issues).update_columns(analyzed_at: nil)
        @now = Time.current
        travel_to @now
      end

      def teardown
        travel_back
      end

      # Structure Tests

      test "returns hash with critical, warning, and total keys" do
        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_kind_of Hash, result
        assert_includes result.keys, :critical
        assert_includes result.keys, :warning
        assert_includes result.keys, :total
      end

      test "critical and warning values are arrays" do
        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_kind_of Array, result[:critical]
        assert_kind_of Array, result[:warning]
      end

      test "each item has required keys" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 20, p95: 400.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        item = (result[:critical] + result[:warning]).first

        assert_includes item.keys, :type
        assert_includes item.keys, :name
        assert_includes item.keys, :reason
        assert_includes item.keys, :metric
        assert_includes item.keys, :metric_sub
        assert_includes item.keys, :link
        assert_includes item.keys, :severity
        assert_includes item.keys, :sort_score
      end

      # Tier Assignment - Routes

      test "route with error rate >= 10% is classified as critical" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 10, p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        critical_routes = result[:critical].select { |i| i[:type] == "ROUTE" }

        assert_equal 1, critical_routes.size
        assert_equal "/api/users", critical_routes.first[:name]
      end

      test "route with P95 >= 3000ms is classified as critical" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 0, p95: 3000.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        critical_routes = result[:critical].select { |i| i[:type] == "ROUTE" }

        assert_equal 1, critical_routes.size
      end

      test "route with error rate >= 5% and < 10% is classified as warning" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 7, p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        warning_routes = result[:warning].select { |i| i[:type] == "ROUTE" }

        assert_equal 0, result[:critical].count { |i| i[:type] == "ROUTE" }
        assert_equal 1, warning_routes.size
      end

      test "route with P95 >= 500ms and < 3000ms is classified as warning" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 0, p95: 800.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        warning_routes = result[:warning].select { |i| i[:type] == "ROUTE" }

        assert_equal 0, result[:critical].count { |i| i[:type] == "ROUTE" }
        assert_equal 1, warning_routes.size
      end

      test "route below all thresholds is not included" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 2, p95: 300.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        route_items = (result[:critical] + result[:warning]).select { |i| i[:type] == "ROUTE" }

        assert_equal 0, route_items.size
      end

      test "route with exactly 10% error rate is classified as critical" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 10, p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        critical_routes = result[:critical].select { |i| i[:type] == "ROUTE" }

        assert_equal 1, critical_routes.size
      end

      test "route with exactly 5% error rate is classified as warning" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 5, p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        warning_routes = result[:warning].select { |i| i[:type] == "ROUTE" }

        assert_equal 1, warning_routes.size
        assert_equal 0, result[:critical].count { |i| i[:type] == "ROUTE" }
      end

      # Tier Assignment - Queries

      test "query with P95 >= 1000ms is classified as critical" do
        query = rails_pulse_queries(:complex_query)
        create_query_summary(query: query, count: 500, p95: 1000.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        critical_queries = result[:critical].select { |i| i[:type] == "QUERY" }

        assert_equal 1, critical_queries.size
      end

      test "query with P95 >= 100ms and < 1000ms is classified as warning" do
        query = rails_pulse_queries(:complex_query)
        create_query_summary(query: query, count: 500, p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        warning_queries = result[:warning].select { |i| i[:type] == "QUERY" }

        assert_equal 0, result[:critical].count { |i| i[:type] == "QUERY" }
        assert_equal 1, warning_queries.size
      end

      test "query with detected critical issues is classified as warning" do
        query = rails_pulse_queries(:query_with_issues)
        query.update_columns(analyzed_at: Time.current)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        warning_queries = result[:warning].select { |i| i[:type] == "QUERY" }

        assert_operator warning_queries.size, :>=, 1
        issue_item = warning_queries.find { |i| i[:name].include?("email") }

        assert_not_nil issue_item
        assert_includes issue_item[:reason], "critical issue"
      end

      test "query with critical issues is not duplicated if already classified by P95" do
        query = rails_pulse_queries(:query_with_issues)
        query.update_columns(analyzed_at: Time.current)
        create_query_summary(query: query, count: 200, p95: 1500.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        query_items = (result[:critical] + result[:warning]).select { |i| i[:type] == "QUERY" && i[:name].include?("email") }

        assert_equal 1, query_items.size
      end

      test "query below P95 threshold with no issues is not included" do
        query = rails_pulse_queries(:simple_query)
        create_query_summary(query: query, count: 100, p95: 50.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        query_items = (result[:critical] + result[:warning]).select { |i| i[:type] == "QUERY" }

        assert_equal 0, query_items.size
      end

      # Tier Assignment - Jobs

      test "job with failure rate >= 10% is classified as critical" do
        RailsPulse::Job.create!(name: "CriticalJob", runs_count: 10, failures_count: 1)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        critical_jobs = result[:critical].select { |i| i[:type] == "JOB" }

        assert_equal 1, critical_jobs.size
        assert_equal "CriticalJob", critical_jobs.first[:name]
      end

      test "job with failure rate >= 5% and < 10% is classified as warning" do
        RailsPulse::Job.create!(name: "WarningRateJob", runs_count: 100, failures_count: 7)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        warning_jobs = result[:warning].select { |i| i[:type] == "JOB" }

        assert_operator warning_jobs.size, :>=, 1
        assert_includes warning_jobs.map { |j| j[:name] }, "WarningRateJob"
      end

      test "job items are excluded when track_jobs is disabled" do
        saved_track_jobs = RailsPulse.configuration.track_jobs
        RailsPulse.configuration.track_jobs = false
        RailsPulse::Job.create!(name: "HighFailureJob", runs_count: 10, failures_count: 9)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        job_items = (result[:critical] + result[:warning]).select { |i| i[:type] == "JOB" }

        assert_equal 0, job_items.size
      ensure
        RailsPulse.configuration.track_jobs = saved_track_jobs
      end

      # Ranking Tests

      test "high absolute error count ranks above high error rate on low traffic" do
        high_volume_route = rails_pulse_routes(:api_users)   # 1000 requests, 12% = 120 errors, score 120000
        low_volume_route  = rails_pulse_routes(:api_posts)   # 20 requests, 50% = 10 errors, score 200

        create_route_summary(route: high_volume_route, count: 1000, errors: 120, p95: 200.0)
        create_route_summary(route: low_volume_route,  count: 20,   errors: 10,  p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        critical_routes = result[:critical].select { |i| i[:type] == "ROUTE" }

        assert_equal 2, critical_routes.size
        assert_equal "/api/users", critical_routes.first[:name]
        assert_equal "/api/posts", critical_routes.last[:name]
      end

      test "items within same tier are sorted by sort_score descending" do
        route_a = rails_pulse_routes(:api_users)  # 1000 requests, 6% = 60 errors, score 60000
        route_b = rails_pulse_routes(:api_posts)  # 200 requests, 8% = 16 errors, score 3200

        create_route_summary(route: route_a, count: 1000, errors: 60, p95: 200.0)
        create_route_summary(route: route_b, count: 200,  errors: 16, p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        warning_routes = result[:warning].select { |i| i[:type] == "ROUTE" }

        assert_equal 2, warning_routes.size
        assert_equal "/api/users", warning_routes.first[:name]
      end

      test "critical items rank above warning items in output" do
        critical_route = rails_pulse_routes(:api_users)
        warning_route  = rails_pulse_routes(:api_posts)

        create_route_summary(route: critical_route, count: 100, errors: 10, p95: 200.0)
        create_route_summary(route: warning_route,  count: 100, errors: 6,  p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_equal 1, result[:critical].count { |i| i[:type] == "ROUTE" }
        assert_equal 1, result[:warning].count { |i| i[:type] == "ROUTE" }
      end

      # 10-item Cap Tests

      test "returns at most 10 items total" do
        routes = [
          rails_pulse_routes(:api_users),
          rails_pulse_routes(:api_posts),
          rails_pulse_routes(:api_test),
          rails_pulse_routes(:api_other),
          rails_pulse_routes(:api_cleanup)
        ]
        queries = [
          rails_pulse_queries(:simple_query),
          rails_pulse_queries(:complex_query),
          rails_pulse_queries(:analyzed_query),
          rails_pulse_queries(:stale_analyzed_query)
        ]

        routes.each { |r| create_route_summary(route: r, count: 100, errors: 15, p95: 200.0) }
        queries.each { |q| create_query_summary(query: q, count: 100, p95: 200.0) }

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_operator result[:total], :<=, 10
        assert_equal result[:total], result[:critical].size + result[:warning].size
      end

      test "critical items are preserved over warning items when hitting cap" do
        routes = [
          rails_pulse_routes(:api_users),
          rails_pulse_routes(:api_posts),
          rails_pulse_routes(:api_test),
          rails_pulse_routes(:api_other),
          rails_pulse_routes(:api_cleanup)
        ]
        queries = [
          rails_pulse_queries(:simple_query),
          rails_pulse_queries(:complex_query),
          rails_pulse_queries(:analyzed_query),
          rails_pulse_queries(:stale_analyzed_query)
        ]

        routes.each { |r| create_route_summary(route: r, count: 100, errors: 20, p95: 200.0) }
        queries.each { |q| create_query_summary(query: q, count: 100, p95: 200.0) }

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_operator result[:critical].size, :>=, result[:warning].size
      end

      # Period Filtering Tests

      test "excludes route summaries outside period range" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 20, p95: 200.0, days_ago: 10)

        result = RailsPulse::Dashboard::NeedsAttention.new(period: 7).to_attention_data

        route_items = (result[:critical] + result[:warning]).select { |i| i[:name] == "/api/users" }

        assert_equal 0, route_items.size
      end

      test "includes route summaries within period range" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 20, p95: 200.0, days_ago: 5)

        result = RailsPulse::Dashboard::NeedsAttention.new(period: 7).to_attention_data

        route_items = (result[:critical] + result[:warning]).select { |i| i[:name] == "/api/users" }

        assert_equal 1, route_items.size
      end

      test "period 30 includes data from 25 days ago" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 20, p95: 200.0, days_ago: 25)

        result = RailsPulse::Dashboard::NeedsAttention.new(period: 30).to_attention_data

        route_items = (result[:critical] + result[:warning]).select { |i| i[:name] == "/api/users" }

        assert_equal 1, route_items.size
      end

      # Regression Tests

      # Regressions answer "what got worse?" where every other rule here answers
      # "what is slow?". A route well under its threshold that tripled is
      # invisible to the threshold rules and must still surface.

      def create_finding(severity: "warning", ratio: 3.0, subject: nil, **overrides)
        route = subject || rails_pulse_routes(:api_users)

        RailsPulse::Finding.create!({
          fingerprint:       SecureRandom.hex(32),
          kind:              "performance_regression",
          subject_type:      "RailsPulse::Route",
          subject_id:        route.id,
          metric:            "p95",
          severity:          severity,
          status:            "open",
          baseline_value:    100.0,
          current_value:     100.0 * ratio,
          delta:             100.0 * (ratio - 1),
          ratio:             ratio,
          baseline_count:    5000,
          current_count:     500,
          first_detected_at: 2.days.ago,
          last_detected_at:  1.hour.ago,
          detection_count:   2
        }.merge(overrides))
      end

      test "surfaces an unresolved regression" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)
        create_finding

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        item = (result[:critical] + result[:warning]).find { |i| i[:type] == "REGRESSION" }

        assert_not_nil item
        assert_equal "/api/users", item[:name]
        assert_equal "200% worse", item[:metric]
      end

      test "surfaces a regression on a route that is nowhere near its threshold" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)
        # 100ms to 300ms: far below the 500ms slow threshold, so no threshold
        # rule would ever report it.
        create_finding(ratio: 3.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_equal 1, result[:total]
      end

      test "does not surface a resolved regression" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)
        create_finding(status: "resolved", resolved_at: 1.day.ago)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_equal 0, result[:total]
      end

      test "surfaces an acknowledged regression" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)
        create_finding(status: "acknowledged")

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_equal 1, result[:total]
      end

      test "a critical regression lands in the critical bucket" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)
        create_finding(severity: "critical")

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_equal 1, result[:critical].size
        assert_empty result[:warning]
      end

      test "a regression with a known change point says when it started" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)
        create_finding(changed_at: 3.days.ago.beginning_of_day, change_point_granularity: "day")

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        item = (result[:critical] + result[:warning]).find { |i| i[:type] == "REGRESSION" }

        assert_includes item[:reason], "started around"
      end

      test "a regression with no change point still reports the regression" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)
        create_finding(changed_at: nil, change_point_granularity: nil)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        item = (result[:critical] + result[:warning]).find { |i| i[:type] == "REGRESSION" }

        assert_includes item[:reason], "vs its own baseline"
      end

      test "regressions are subject to the same 10-item cap" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)
        routes = [
          rails_pulse_routes(:api_users),
          rails_pulse_routes(:api_posts),
          rails_pulse_routes(:api_test),
          rails_pulse_routes(:api_other),
          rails_pulse_routes(:api_cleanup)
        ]
        # Two findings per route on different metrics, for 10, plus two more.
        routes.each do |route|
          create_finding(subject: route, metric: "p95")
          create_finding(subject: route, metric: "error_rate", kind: "error_rate_regression")
        end
        create_finding(subject: routes.first, metric: "p99")
        create_finding(subject: routes.last, metric: "p50")

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_operator result[:total], :<=, 10
      end

      # Edge Cases

      test "returns empty results when no route or query issues exist and summary is fresh" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_equal 0, result[:total]
        assert_empty result[:critical]
        assert_empty result[:warning]
      end

      test "handles route with zero requests gracefully" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 0, errors: 0, p95: 0.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        route_items = (result[:critical] + result[:warning]).select { |i| i[:type] == "ROUTE" }

        assert_equal 0, route_items.size
      end

      test "total matches sum of critical and warning sizes" do
        route = rails_pulse_routes(:api_users)
        query = rails_pulse_queries(:complex_query)

        create_route_summary(route: route, count: 100, errors: 15, p95: 200.0)
        create_query_summary(query: query, count: 100, p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_equal result[:total], result[:critical].size + result[:warning].size
      end

      test "route with P95 triggering critical overrides warning-level error rate" do
        route = rails_pulse_routes(:api_users)
        create_route_summary(route: route, count: 100, errors: 6, p95: 3500.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        critical_routes = result[:critical].select { |i| i[:type] == "ROUTE" }

        assert_equal 1, critical_routes.size
      end

      test "query items include monospace flag" do
        query = rails_pulse_queries(:complex_query)
        create_query_summary(query: query, count: 100, p95: 200.0)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data
        query_item = (result[:critical] + result[:warning]).find { |i| i[:type] == "QUERY" }

        assert query_item[:monospace]
      end

      # Storage Pressure Tests

      test "storage pressure critical item appears in critical when summary job has never run" do
        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        storage_items = result[:critical].select { |i| i[:type] == "STORAGE" }

        assert_operator storage_items.size, :>=, 1
      end

      test "storage pressure items appear outside the 10-item cap" do
        # Fill cap with 10 critical route items
        routes = [
          rails_pulse_routes(:api_users), rails_pulse_routes(:api_posts),
          rails_pulse_routes(:api_test), rails_pulse_routes(:api_other),
          rails_pulse_routes(:api_cleanup)
        ]
        queries = [
          rails_pulse_queries(:simple_query), rails_pulse_queries(:complex_query),
          rails_pulse_queries(:analyzed_query), rails_pulse_queries(:stale_analyzed_query)
        ]
        routes.each  { |r| create_route_summary(route: r, count: 100, errors: 20, p95: 200.0) }
        queries.each { |q| create_query_summary(query: q, count: 100, p95: 200.0) }

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        # Storage items should appear even though cap is full
        storage_items = (result[:critical] + result[:warning]).select { |i| i[:type] == "STORAGE" }

        assert_operator storage_items.size, :>=, 1
      end

      test "no storage pressure items when summary is fresh" do
        create_overall_hourly_summary(period_end: 30.minutes.ago)

        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        storage_items = (result[:critical] + result[:warning]).select { |i| i[:type] == "STORAGE" }

        assert_empty storage_items
      end

      test "total count includes storage pressure items" do
        # No summaries exist → will generate a storage critical item
        result = RailsPulse::Dashboard::NeedsAttention.new.to_attention_data

        assert_equal result[:total], result[:critical].size + result[:warning].size
        assert_operator result[:total], :>=, 1
      end

      private

      def create_overall_hourly_summary(period_end:)
        RailsPulse::Summary.create!(
          summarizable_type: "RailsPulse::Request",
          summarizable_id:   0,
          period_type:       "hour",
          period_start:      period_end.beginning_of_hour,
          period_end:        period_end,
          count:             1,
          avg_duration:      100.0
        )
      end

      def create_route_summary(route:, count:, errors:, p95:, days_ago: 2)
        period_start = days_ago.days.ago.beginning_of_day
        RailsPulse::Summary.create!(
          summarizable_type: "RailsPulse::Route",
          summarizable_id:   route.id,
          period_start:      period_start,
          period_end:        period_start.end_of_day,
          period_type:       "day",
          count:             count,
          error_count:       errors,
          avg_duration:      p95 * 0.7,
          p95_duration:      p95
        )
      end

      def create_query_summary(query:, count:, p95:, days_ago: 2)
        period_start = days_ago.days.ago.beginning_of_day
        RailsPulse::Summary.create!(
          summarizable_type: "RailsPulse::Query",
          summarizable_id:   query.id,
          period_start:      period_start,
          period_end:        period_start.end_of_day,
          period_type:       "day",
          count:             count,
          avg_duration:      p95 * 0.7,
          p95_duration:      p95
        )
      end
    end
  end
end
