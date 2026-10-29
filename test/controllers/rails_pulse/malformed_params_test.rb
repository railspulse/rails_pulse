require "test_helper"

# A hand-edited URL can turn any query-string value into an array
# (`page[]=`) or a hash (`page[a]=`). Every dashboard page should ignore a
# value of the wrong shape and fall back to its default, not 500.
class RailsPulse::MalformedParamsTest < ActionDispatch::IntegrationTest
  fixtures :rails_pulse_routes, :rails_pulse_requests, :rails_pulse_queries,
    :rails_pulse_jobs, :rails_pulse_job_runs, :rails_pulse_summaries

  def setup
    ENV["TEST_TYPE"] = "functional"
    super
    @route = rails_pulse_routes(:api_test)
    @job = rails_pulse_jobs(:report_job)
  end

  # Time Range Params

  test "array period_start_range falls back to the default range" do
    get rails_pulse.routes_path, params: { q: { period_start_range: [ "x" ] } }

    assert_response :success
  end

  test "hash period_start_range falls back to the default range" do
    get rails_pulse.routes_path, params: { q: { period_start_range: { a: "b" } } }

    assert_response :success
  end

  test "array duration filter is ignored" do
    get rails_pulse.requests_path, params: { q: { duration: [ "" ] } }

    assert_response :success
  end

  test "array custom_date_range is ignored" do
    get rails_pulse.routes_path, params: { q: { period_start_range: "custom", custom_date_range: [ "a to b" ] } }

    assert_response :success
  end

  test "custom_date_range with nothing after the separator is ignored" do
    get rails_pulse.routes_path, params: { q: { period_start_range: "custom", custom_date_range: "a to " } }

    assert_response :success
  end

  test "array chart zoom bounds are ignored" do
    get rails_pulse.requests_path, params: { q: { occurred_at_gteq: [ "x" ], occurred_at_lt: [ "y" ] } }

    assert_response :success
  end

  test "array selected_column_time is ignored" do
    get rails_pulse.routes_path, params: { selected_column_time: [ "1" ] }

    assert_response :success
  end

  test "array zoom times are ignored" do
    get rails_pulse.routes_path, params: { zoom_start_time: [ "1" ], zoom_end_time: [ "2" ] }

    assert_response :success
  end

  test "hash zoom times are ignored" do
    get rails_pulse.queries_path, params: { zoom_start_time: { a: "1" }, zoom_end_time: { a: "2" } }

    assert_response :success
  end

  # Pagination Params

  test "array page falls back to the first page" do
    get rails_pulse.routes_path, params: { page: [ "" ] }

    assert_response :success
  end

  test "hash page falls back to the first page" do
    get rails_pulse.requests_path, params: { page: { a: "2" } }

    assert_response :success
  end

  test "array limit falls back to the default limit" do
    get rails_pulse.routes_path, params: { limit: [ "" ] }

    assert_response :success
  end

  test "array limit on the pagination endpoint leaves the session limit alone" do
    patch rails_pulse.pagination_limit_path, params: { limit: 25 }
    patch rails_pulse.pagination_limit_path, params: { limit: [ "30" ] }

    assert_response :success
    assert_equal 25, session[:pagination_limit]
  end

  test "hash limit on the pagination endpoint is ignored" do
    patch rails_pulse.pagination_limit_path, params: { limit: { a: "30" } }

    assert_response :success
    assert_nil session[:pagination_limit]
  end

  # Sort Params

  test "hash sort is ignored on every index" do
    paths = [
      rails_pulse.routes_path, rails_pulse.requests_path, rails_pulse.queries_path,
      rails_pulse.jobs_path, rails_pulse.job_runs_path(@job),
      rails_pulse.deployments_path, rails_pulse.exceptions_path
    ]

    paths.each do |path|
      get path, params: { q: { s: { a: "b" } } }

      assert_response :success, "expected #{path} to ignore a hash sort"
    end
  end

  test "array sort is ignored" do
    get rails_pulse.routes_path, params: { q: { s: [ { a: "b" } ] } }

    assert_response :success
  end

  # Show Pages

  test "route show tolerates a non-hash q param" do
    get rails_pulse.route_path(@route), params: { q: "foo" }

    assert_response :success
  end

  test "job show tolerates a non-hash q param" do
    get rails_pulse.job_path(@job), params: { q: "foo" }

    assert_response :success
  end

  test "route show with an array custom_date_range renders an empty picker" do
    get rails_pulse.route_path(@route), params: { q: { period_start_range: "custom", custom_date_range: [ "x" ] } }

    assert_response :success
  end

  # Tags

  test "array tag is rejected" do
    post rails_pulse.add_tag_path("route", @route.id), params: { tag: [ "x" ] }

    assert_response :redirect
    assert_equal "Tag cannot be blank", flash[:alert]
  end

  test "hash tag is rejected" do
    post rails_pulse.add_tag_path("route", @route.id), params: { tag: { a: "x" } }

    assert_response :redirect
    assert_equal "Tag cannot be blank", flash[:alert]
  end

  test "array tag on remove is rejected" do
    delete rails_pulse.remove_tag_path("route", @route.id), params: { tag: [ "x" ] }

    assert_response :redirect
    assert_equal "Failed to remove tag", flash[:alert]
  end
end
