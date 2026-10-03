require "test_helper"

module RailsPulse
  class PeriodInsightsTest < ActiveSupport::TestCase
    fixtures :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_jobs

    # Default thresholds: routes slow 500 / critical 3000, queries slow 100 /
    # critical 1000, jobs slow 5000 / critical 60000.
    FROZEN_NOW = Time.zone.parse("2026-06-15 12:00:00").freeze

    def setup
      travel_to FROZEN_NOW
      RailsPulse::Summary.delete_all
      @period_start = Time.current.beginning_of_week - 1.week
      @route = rails_pulse_routes(:api_users)
      @query = rails_pulse_queries(:simple_query)
      @job   = rails_pulse_jobs(:mailer_job)
      @track_jobs = RailsPulse.configuration.track_jobs
    end

    def teardown
      RailsPulse.configuration.track_jobs = @track_jobs
      travel_back
    end

    # Structure Tests

    test "returns empty insights when no summaries exist" do
      result = insights_for

      assert_empty result[:critical]
      assert_empty result[:warning]
      assert_equal 0, result[:total]
    end

    test "an item names its record by id and carries no sort score" do
      summary_for(@route, p95: 3000.0)
      item = insights_for[:critical].first

      assert_equal "route", item[:type]
      assert_equal @route.id, item[:id]
      assert_equal "GET /api/users", item[:name]
      assert_equal :critical, item[:severity]
      assert_not item.key?(:sort_score)
    end

    test "reads only the requested period" do
      summary_for(@route, p95: 3000.0, period_start: @period_start - 1.week)
      summary_for(@route, p95: 3000.0, period_type: "day", period_start: @period_start)

      assert_equal 0, insights_for[:total]
    end

    # Route Classification

    test "route below all thresholds is not included" do
      summary_for(@route, p95: 100.0)

      assert_equal 0, insights_for[:total]
    end

    test "route with P95 at the critical threshold is critical" do
      summary_for(@route, p95: 3000.0)
      result = insights_for

      assert_equal 1, result[:critical].size
      assert_empty result[:warning]
    end

    test "route with P95 at the slow threshold is a warning" do
      summary_for(@route, p95: 500.0)
      result = insights_for

      assert_empty result[:critical]
      assert_equal 1, result[:warning].size
    end

    test "route with a 10% error rate is critical" do
      summary_for(@route, p95: 100.0, count: 100, errors: 10)
      result = insights_for

      assert_equal 1, result[:critical].size
      assert_includes result[:critical].first[:reason], "10.0% error rate · 100 requests this period"
    end

    test "route with a 5% error rate and P95 below slow is a warning" do
      summary_for(@route, p95: 100.0, count: 100, errors: 5)
      result = insights_for

      assert_empty result[:critical]
      assert_includes result[:warning].first[:reason], "5.0% error rate"
    end

    # Query Classification

    test "query with P95 at the critical threshold is critical" do
      summary_for(@query, p95: 1000.0, count: 50)
      item = insights_for[:critical].first

      assert_equal "query", item[:type]
      assert_equal @query.id, item[:id]
      assert_equal "50 executions", item[:metric_sub]
    end

    test "query with P95 at the slow threshold is a warning" do
      summary_for(@query, p95: 100.0, count: 50)

      assert_equal 1, insights_for[:warning].size
    end

    test "query below the slow threshold is not included" do
      summary_for(@query, p95: 99.0, count: 50)

      assert_equal 0, insights_for[:total]
    end

    test "query SQL is truncated at 80 characters" do
      @query.update!(normalized_sql: "SELECT " + ("a" * 80))
      summary_for(@query, p95: 200.0, count: 50)
      name = insights_for[:warning].first[:name]

      assert name.end_with?("...")
      assert_equal 83, name.length
    end

    # Job Classification

    test "jobs are left out when track_jobs is disabled" do
      RailsPulse.configuration.track_jobs = false
      summary_for(@job, p95: 70_000.0, count: 10, errors: 2)

      assert_equal 0, insights_for[:total]
    end

    test "job with a 10% failure rate is critical" do
      summary_for(@job, p95: 1000.0, count: 10, errors: 1)
      item = insights_for[:critical].first

      assert_equal "job", item[:type]
      assert_equal "mailers queue · 10.0% failure rate", item[:reason]
      assert_equal "1 / 10 failed", item[:metric]
    end

    test "job with a 5% failure rate is a warning" do
      summary_for(@job, p95: 1000.0, count: 100, errors: 5)

      assert_equal 1, insights_for[:warning].size
    end

    test "job with P95 at the critical threshold is critical" do
      summary_for(@job, p95: 60_000.0, count: 10)

      assert_equal 1, insights_for[:critical].size
    end

    test "job with P95 at the slow threshold is a warning" do
      summary_for(@job, p95: 5_000.0, count: 10)

      assert_equal 1, insights_for[:warning].size
    end

    # Ordering and Cap

    test "caps output at 10 items" do
      11.times do |i|
        route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/cap-test-#{i}", controller_action: "cap#test#{i}")
        summary_for(route, p95: 600.0)
      end

      assert_equal 10, insights_for[:total]
    end

    test "critical items fill the cap before warnings" do
      10.times do |i|
        route = RailsPulse::Route.create!(http_methods: '["GET"]', path: "/critical-#{i}", controller_action: "critical#test#{i}")
        summary_for(route, p95: 3000.0)
      end
      summary_for(@route, p95: 600.0)
      result = insights_for

      assert_equal 10, result[:critical].size
      assert_empty result[:warning]
    end

    test "items of the same severity are ordered worst first" do
      summary_for(@route, p95: 600.0)
      summary_for(rails_pulse_routes(:api_posts), p95: 900.0)
      names = insights_for[:warning].map { |i| i[:name] }

      assert_equal [ "POST /api/posts", "GET /api/users" ], names
    end

    private

    def insights_for(period_type: "week")
      PeriodInsights.new(period_type: period_type, period_start: @period_start).to_insights_data
    end

    def summary_for(record, p95:, count: 100, errors: 0, period_type: "week", period_start: @period_start)
      RailsPulse::Summary.create!(
        summarizable:  record,
        period_type:   period_type,
        period_start:  period_start,
        period_end:    RailsPulse::Summary.calculate_period_end(period_type, period_start),
        count:         count,
        avg_duration:  p95 / 2,
        p95_duration:  p95,
        error_count:   errors,
        success_count: count - errors
      )
    end
  end
end
