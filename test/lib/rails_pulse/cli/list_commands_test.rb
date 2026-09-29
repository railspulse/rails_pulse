require "test_helper"
require "rails_pulse/cli/routes"
require "rails_pulse/cli/requests"
require "rails_pulse/cli/queries"
require "rails_pulse/cli/jobs"
require "rails_pulse/cli/job_runs"
require "rails_pulse/cli/exceptions"
require "rails_pulse/cli/deployments"
require "rails_pulse/cli/coverage"

module RailsPulse
  module CLI
    # Shared behaviour for all simple list commands (routes, requests, queries, jobs, deployments).
    # Each command calls client.get(endpoint, params) and renders via Formatter.render.
    class ListCommandsTest < ActiveSupport::TestCase
      include ApiClientTestHelpers

      LIST_RESPONSE = {
        "data" => [],
        "meta" => { "total" => 0, "limit" => 25, "offset" => 0 }
      }.freeze

      def setup
        ENV["RAILS_PULSE_URL"]   = "https://example.com"
        ENV["RAILS_PULSE_TOKEN"] = "test-token"
      end

      def teardown
        ENV.delete("RAILS_PULSE_URL")
        ENV.delete("RAILS_PULSE_TOKEN")
        restore_net_http_start
      end

      def captured_params
        @captured_params ||= {}
      end

      def stub_list(response = LIST_RESPONSE)
        stub_http_response(200, response.to_json) do |_req, uri|
          @captured_uri    = uri
          @captured_params = URI.decode_www_form(uri.query.to_s).to_h
        end
      end

      def run_cmd(klass, options = {})
        defaults = { "limit" => 25, "offset" => 0, "json" => false }
        cmd = klass.new([], defaults.merge(options.transform_keys(&:to_s)))
        capture_io { cmd.list }
      end

      # --- Routes ---

      test "routes list calls /routes endpoint" do
        stub_list
        run_cmd(Routes)

        assert_includes @captured_uri.path, "/routes"
      end

      test "routes list passes limit and offset" do
        stub_list
        run_cmd(Routes, limit: 10, offset: 5)

        assert_equal "10", captured_params["limit"]
        assert_equal "5",  captured_params["offset"]
      end

      test "routes list renders JSON when json: true" do
        stub_list
        out, _err = run_cmd(Routes, json: true)

        assert_nothing_raised { JSON.parse(out) }
      end

      test "routes list passes since, until, search, and sort when provided" do
        stub_list
        run_cmd(Routes, since: "2026-06-01T00:00:00Z", until: "2026-06-02T00:00:00Z", search: "checkout", sort: "avg_duration")

        assert_equal "2026-06-01T00:00:00Z", captured_params["since"]
        assert_equal "2026-06-02T00:00:00Z", captured_params["until"]
        assert_equal "checkout", captured_params["search"]
        assert_equal "avg_duration", captured_params["sort"]
      end

      test "routes list renders methods and action, switching to stats columns when present" do
        plain = { "data" => [ { "http_methods" => %w[GET POST], "path" => "/x", "controller_action" => "XController#show", "created_at" => "t", "stats" => nil } ], "meta" => {} }
        out, _err = (stub_list(plain); run_cmd(Routes))

        assert_match(/GET\|POST\s+\/x\s+XController#show/, out)
        refute_includes out, "REQUESTS"

        with_stats = { "data" => [ { "http_methods" => [ "GET" ], "path" => "/x", "controller_action" => nil, "created_at" => "t",
                                     "stats" => { "request_count" => 42, "avg_duration_ms" => 12.5, "error_count" => 3 } } ], "meta" => {} }
        out, _err = (stub_list(with_stats); run_cmd(Routes, since: "2026-06-01T00:00:00Z"))

        assert_includes out, "REQUESTS"
        assert_match(/42\s+12\.5\s+3/, out)
      end

      test "routes list exits with error message on API error" do
        stub_http_response(401, '{"error":"Unauthorized"}')

        err = assert_raises(SystemExit) { run_cmd(Routes) }

        assert_equal 1, err.status
      end

      # --- Requests ---

      test "requests list calls /requests endpoint" do
        stub_list
        run_cmd(Requests)

        assert_includes @captured_uri.path, "/requests"
      end

      test "requests list passes since and until when provided" do
        stub_list
        run_cmd(Requests, since: "2026-06-01T00:00:00Z", until: "2026-06-07T23:59:59Z")

        assert_equal "2026-06-01T00:00:00Z", captured_params["since"]
        assert_equal "2026-06-07T23:59:59Z", captured_params["until"]
      end

      test "requests list omits since and until when not provided" do
        stub_list
        run_cmd(Requests)

        refute_includes captured_params.keys, "since"
        refute_includes captured_params.keys, "until"
      end

      test "requests list passes status when provided" do
        stub_list
        run_cmd(Requests, status: "5xx")

        assert_equal "5xx", captured_params["status"]
      end

      # --- Queries ---

      test "queries list calls /queries endpoint" do
        stub_list
        run_cmd(Queries)

        assert_includes @captured_uri.path, "/queries"
      end

      test "queries list passes since and until when provided" do
        stub_list
        run_cmd(Queries, since: "2026-06-01T00:00:00Z", until: "2026-06-07T23:59:59Z")

        assert_equal "2026-06-01T00:00:00Z", captured_params["since"]
        assert_equal "2026-06-07T23:59:59Z", captured_params["until"]
      end

      test "queries list omits since and until when not provided" do
        stub_list
        run_cmd(Queries)

        refute_includes captured_params.keys, "since"
        refute_includes captured_params.keys, "until"
        refute_includes captured_params.keys, "sort"
      end

      test "queries list passes sort and renders stats columns when present" do
        with_stats = { "data" => [ { "id" => 7, "normalized_sql" => "SELECT 1", "analyzed_at" => nil,
                                     "stats" => { "executions" => 90, "avg_duration_ms" => 2.5, "max_duration_ms" => 9.0, "total_duration_ms" => 225.0, "max_repetition_count" => 12 } } ],
                       "meta" => {} }
        stub_list(with_stats)
        out, _err = run_cmd(Queries, sort: "total_duration")

        assert_equal "total_duration", captured_params["sort"]
        assert_includes out, "EXECS"
        assert_match(/SELECT 1\s+90\s+2\.5\s+9\.0\s+225\.0\s+12/, out)
      end

      test "queries list keeps the plain columns without stats" do
        stub_list("data" => [ { "id" => 7, "normalized_sql" => "SELECT 1", "analyzed_at" => "t", "stats" => nil } ], "meta" => {})
        out, _err = run_cmd(Queries)

        refute_includes out, "EXECS"
        assert_includes out, "ANALYZED"
      end

      # --- Jobs ---

      test "jobs list calls /jobs endpoint" do
        stub_list
        run_cmd(Jobs)

        assert_includes @captured_uri.path, "/jobs"
      end

      test "jobs list passes status when provided" do
        stub_list
        run_cmd(Jobs, status: "failed")

        assert_equal "failed", captured_params["status"]
      end

      test "jobs list omits status when not provided" do
        stub_list
        run_cmd(Jobs)

        refute_includes captured_params.keys, "status"
      end

      # --- JobRuns ---

      test "job_runs list calls /job_runs with status, job, and time filters" do
        stub_list
        run_cmd(JobRuns, status: "failed", job: "ReportJob", since: "2026-06-01T00:00:00Z", until: "2026-06-02T00:00:00Z")

        assert_includes @captured_uri.path, "/job_runs"
        assert_equal "failed", captured_params["status"]
        assert_equal "ReportJob", captured_params["job"]
        assert_equal "2026-06-01T00:00:00Z", captured_params["since"]
        assert_equal "2026-06-02T00:00:00Z", captured_params["until"]
      end

      test "job_runs list omits optional filters and renders a table" do
        stub_list("data" => [ { "id" => 1, "job_name" => "ReportJob", "status" => "failed", "occurred_at" => "t", "duration" => 1.5, "error_class" => "Boom" } ],
                  "meta" => { "total" => 1 })
        out, _err = run_cmd(JobRuns)

        assert_equal %w[limit offset], captured_params.keys
        assert_includes out, "ReportJob"
        assert_includes out, "Boom"
      end

      # --- Exceptions ---

      test "exceptions list calls /exceptions with every filter" do
        stub_list("data" => [
          { "id" => 7, "exception_class" => "ActiveRecord::RecordNotFound", "location" => "app/models/post.rb#find",
            "status" => "open", "occurrence_count" => 5, "last_seen_at" => "2026-06-01T12:00:00Z" }
        ], "meta" => { "total" => 1 })
        out, _err = run_cmd(Exceptions, status: "open", search: "RecordNotFound", sort: "occurrence_count",
                                        since: "2026-06-01T00:00:00Z", until: "2026-06-07T23:59:59Z")

        assert_includes @captured_uri.path, "/exceptions"
        assert_equal "open", captured_params["status"]
        assert_equal "RecordNotFound", captured_params["search"]
        assert_equal "occurrence_count", captured_params["sort"]
        assert_equal "2026-06-01T00:00:00Z", captured_params["since"]
        assert_equal "2026-06-07T23:59:59Z", captured_params["until"]
        assert_match(/RecordNotFound.*post\.rb#find.*open.*5/, out)
      end

      test "exceptions show fetches one group and prints its occurrences and backtrace" do
        stub_list("data" => {
          "id" => 42, "exception_class" => "ZeroDivisionError", "location" => "app/services/calc.rb#divide",
          "status" => "open", "occurrence_count" => 2, "message" => "divided by 0",
          "first_seen_at" => "t0", "last_seen_at" => "t1",
          "occurrences" => [ { "occurred_at" => "t1", "request_method" => "POST", "request_url" => "/calc",
                               "environment" => "production", "request_params" => { "n" => "0" },
                               "backtrace" => [ { "file" => "app/services/calc.rb", "line" => 7, "method" => "divide" },
                                                { "file" => "gems/x.rb", "line" => 1, "method" => "call" } ] } ]
        })
        cmd = Exceptions.new([], { "occurrences" => 3, "json" => false })
        out, _err = capture_io { cmd.show("42") }

        assert_includes @captured_uri.path, "/exceptions/42"
        assert_equal "3", captured_params["occurrences"]
        assert_includes out, "ZeroDivisionError  #42"
        assert_includes out, "POST /calc"
        assert_includes out, "app/services/calc.rb:7 in divide"
        assert_includes out, "gems/x.rb:1"
      end

      test "exceptions show prints JSON when asked" do
        stub_list("data" => { "id" => 42, "occurrences" => [] })
        cmd = Exceptions.new([], { "occurrences" => 3, "json" => true })
        out, _err = capture_io { cmd.show("42") }

        assert_equal 42, JSON.parse(out)["data"]["id"]
      end

      test "exceptions list omits filters when not provided" do
        stub_list
        run_cmd(Exceptions)

        assert_equal %w[limit offset], captured_params.keys
      end

      # --- Coverage ---

      COVERAGE_RESPONSE = {
        "as_of" => "2026-09-26T12:00:00Z",
        "telemetry" => {
          "requests" => { "oldest" => "2026-08-27T12:00:00Z", "newest" => "2026-09-26T11:59:00Z", "count" => 5000, "tracked" => true },
          "exceptions" => { "tracked" => false, "reason" => "config.track_exceptions is false" }
        },
        "summaries" => { "hourly_from" => "2026-09-24T12:00:00Z", "hourly_through" => "2026-09-26T11:00:00Z", "stale" => false },
        "retention" => { "raw_records" => { "days" => 30.0 }, "hourly_summaries" => { "days" => 2.0 }, "events" => { "days" => 90.0 } },
        "collection" => { "known" => true, "live_writers" => 2, "queue_depth" => 0, "queue_size" => 1000,
                          "dropped_last_hour" => 0, "last_heartbeat_at" => "2026-09-26T11:59:30Z", "gap_suspected" => false }
      }.freeze

      def run_coverage(options = {})
        cmd = Coverage.new([], { "json" => false }.merge(options.transform_keys(&:to_s)))
        capture_io { cmd.show }
      end

      test "coverage show calls /coverage and prints each section" do
        stub_list(COVERAGE_RESPONSE)
        out, _err = run_coverage

        assert_includes @captured_uri.path, "/coverage"
        assert_match(/Telemetry/, out)
        assert_match(/Summaries/, out)
        assert_match(/Retention/, out)
        assert_match(/Collection/, out)
      end

      test "coverage show names a kind that is not tracked" do
        stub_list(COVERAGE_RESPONSE)
        out, _err = run_coverage

        assert_match(/exceptions\s+not tracked/, out)
      end

      test "coverage show prints raw JSON with --json" do
        stub_list(COVERAGE_RESPONSE)
        out, _err = run_coverage(json: true)

        assert_equal COVERAGE_RESPONSE, JSON.parse(out)
      end

      # --- Deployments ---

      test "deployments list calls /deployments with time filters and renders a table" do
        stub_list("data" => [
          { "short_revision" => "abc123", "started_at" => "t1", "finished_at" => "t2" },
          { "short_revision" => "def456", "started_at" => "t3", "finished_at" => nil }
        ], "meta" => { "total" => 2 })
        out, _err = run_cmd(Deployments, since: "2026-06-01T00:00:00Z", until: "2026-06-07T23:59:59Z")

        assert_includes @captured_uri.path, "/deployments"
        assert_equal "2026-06-01T00:00:00Z", captured_params["since"]
        assert_equal "2026-06-07T23:59:59Z", captured_params["until"]
        assert_match(/abc123\s+t1\s+t2/, out)
        assert_match(/def456\s+t3/, out)
      end

      test "deployments list omits since and until when not provided" do
        stub_list
        run_cmd(Deployments)

        assert_equal %w[limit offset], captured_params.keys
      end
    end
  end
end
