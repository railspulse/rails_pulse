require "test_helper"

# Detail capture from request to dashboard (decision 0022): real requests
# through the dummy app, folded by the writer, flushed to rollups, summarized,
# and rendered. The stage-by-stage tests stub each seam; this one doesn't.
class RailsPulse::Middleware::DetailCaptureEndToEndTest < ActionDispatch::IntegrationTest
  HOUR = Time.zone.parse("2026-10-14 10:00:00")

  setup do
    config = RailsPulse.configuration
    @original_settings = %i[store_full_details request_thresholds query_thresholds].index_with { |key| config.public_send(key) }
    RailsPulse::SchemaCheck.reset!
    RailsPulse::Tracker.reset_rollups!
    # Nothing is slow enough to keep on its own; the sample roll decides.
    config.request_thresholds = config.request_thresholds.merge(slow: 60_000)
    config.query_thresholds = config.query_thresholds.merge(slow: 60_000)
    config.store_full_details = { above: :slow, sample_rate: 0.5 }
    travel_to HOUR + 20.minutes
  end

  teardown do
    travel_back
    @original_settings.each { |key, value| RailsPulse.configuration.public_send("#{key}=", value) }
    RailsPulse::Tracker.reset_rollups!
    RailsPulse::SchemaCheck.reset!
  end

  # Capture Tests

  test "unsampled requests fold into rollups and sampled ones are kept in full" do
    assert_difference "RailsPulse::Request.count", 1 do
      folded_get "/fast", times: 3
      kept_get "/fast"
    end

    assert_no_difference "RailsPulse::Rollup.count" do
      folded_get "/fast"
    end

    RailsPulse::Tracker.flush!

    route = RailsPulse::Route.find_by!(controller_action: "home#fast")
    rollup = RailsPulse::Rollup.find_by!(rollupable: route, period_start: HOUR)

    assert_equal 4, rollup.count
    assert_equal 4, rollup.status_2xx
    assert_operator RailsPulse::Request.find_by!(route: route).operations.count, :>, 0
  end

  test "a folded request's SQL is counted in its query's rollup" do
    folded_get "/fast", times: 2
    RailsPulse::Tracker.flush!

    query = users_count_query

    assert_equal 2, RailsPulse::Rollup.find_by!(rollupable: query, period_start: HOUR).count
    assert_equal 0, RailsPulse::Operation.where(query: query).count
  end

  test "a second flush overwrites the writer's row with the running total" do
    folded_get "/fast", times: 2
    RailsPulse::Tracker.flush!
    folded_get "/fast", times: 3

    assert_no_difference "RailsPulse::Rollup.count" do
      RailsPulse::Tracker.flush!
    end

    route = RailsPulse::Route.find_by!(controller_action: "home#fast")

    assert_equal 5, RailsPulse::Rollup.find_by!(rollupable: route).count
  end

  # Summary Tests

  test "the hour's summary counts kept and folded requests together" do
    folded_get "/fast", times: 3
    kept_get "/fast"
    folded_get "/api_simple", times: 2
    RailsPulse::Tracker.flush!

    summarize_hour

    fast = RailsPulse::Route.find_by!(controller_action: "home#fast")
    fast_summary = route_summary(fast)
    kept_duration = RailsPulse::Request.where(route: fast).sum(:duration).to_f
    folded_duration = RailsPulse::Rollup.where(rollupable: fast).sum(:sum_duration).to_f

    assert_equal 4, fast_summary.count
    assert_in_delta kept_duration + folded_duration, fast_summary.total_duration.to_f, 0.01
    assert_equal 4, fast_summary.success_count

    overall = RailsPulse::Summary.find_by!(summarizable_type: "RailsPulse::Request", summarizable_id: 0,
                                           period_type: "hour", period_start: HOUR)

    assert_equal 6, overall.count
  end

  test "a route whose every request was folded still gets a summary" do
    folded_get "/api_simple", times: 3
    RailsPulse::Tracker.flush!

    summarize_hour

    route = RailsPulse::Route.find_by!(controller_action: "home#api_simple")

    assert_equal 0, RailsPulse::Request.where(route: route).count
    assert_equal 3, route_summary(route).count
  end

  test "a query's summary counts every execution, folded ones included" do
    folded_get "/fast", times: 3
    kept_get "/fast"
    RailsPulse::Tracker.flush!

    summarize_hour

    query = users_count_query
    summary = RailsPulse::Summary.find_by!(summarizable: query, period_type: "hour", period_start: HOUR)

    assert_equal 4, summary.count
  end

  # Dashboard Tests

  test "route and query pages render for data that exists only in rollups" do
    folded_get "/fast", times: 3
    RailsPulse::Tracker.flush!
    summarize_hour

    route = RailsPulse::Route.find_by!(controller_action: "home#fast")
    query = users_count_query

    get rails_pulse.route_path(route)

    assert_response :success
    assert_includes response.body, "This list shows only captured requests"

    get rails_pulse.query_path(query)

    assert_response :success
    assert_includes response.body, "Diagnostics, locations and raw data come only from captured requests"
  end

  # Edge Cases

  test "with store_full_details :all every request is kept and no rollups are written" do
    RailsPulse.configuration.store_full_details = :all

    assert_difference "RailsPulse::Request.count", 3 do
      3.times { request_path("/fast") }
    end

    assert_no_difference "RailsPulse::Rollup.count" do
      RailsPulse::Tracker.flush!
    end
  end

  test "an hour with no traffic summarizes to an empty heartbeat row" do
    summarize_hour

    overall = RailsPulse::Summary.find_by!(summarizable_type: "RailsPulse::Request", summarizable_id: 0,
                                           period_type: "hour", period_start: HOUR)

    assert_equal 0, overall.count
  end

  private

  # The middleware rolls Kernel.rand against sample_rate (0.5 here): a roll
  # above it folds the request, a roll below keeps it.
  def folded_get(path, times: 1)
    Kernel.stubs(:rand).returns(0.99)
    times.times { request_path(path) }
  ensure
    Kernel.unstub(:rand)
  end

  def kept_get(path)
    Kernel.stubs(:rand).returns(0.0)
    request_path(path)
  ensure
    Kernel.unstub(:rand)
  end

  # Integration tests share one connection across requests, so without this
  # a later request's repeated SELECT can be answered from the previous
  # request's query cache, and the subscriber rightly skips cached SQL.
  def request_path(path)
    ActiveRecord::Base.connection.clear_query_cache
    get path

    assert_response :success
  end

  def summarize_hour
    travel_to(HOUR + 1.hour + 5.minutes) { RailsPulse::SummaryService.new("hour", HOUR).perform }
  end

  # The query /fast runs, as normalized SQL. Table quoting differs by
  # adapter (backticks on MySQL), so it comes from the host's connection.
  def users_count_query
    RailsPulse::Query.find_by!(normalized_sql: "SELECT COUNT(*) FROM #{ActiveRecord::Base.connection.quote_table_name("users")}")
  end

  def route_summary(route)
    RailsPulse::Summary.find_by!(summarizable: route, period_type: "hour", period_start: HOUR)
  end
end
