require "test_helper"

module RailsPulse
  module Api
    module V1
      class CoverageControllerTest < ActionDispatch::IntegrationTest
        VALID_TOKEN = "test-api-token"

        # Heartbeats come from the background writer, which only exists with
        # config.async; the suite itself writes inline.
        setup do
          RailsPulse.configuration.api_token = VALID_TOKEN
          @original_async = RailsPulse.configuration.async
          RailsPulse.configuration.async = true
        end

        teardown do
          RailsPulse.configuration.api_token = nil
          RailsPulse.configuration.async = @original_async
        end

        def get_coverage
          get rails_pulse.api_v1_coverage_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          JSON.parse(response.body)
        end

        # Structure Tests

        test "returns 401 without token" do
          get rails_pulse.api_v1_coverage_path

          assert_response :unauthorized
        end

        test "returns the four coverage sections" do
          body = get_coverage

          assert_response :success
          %w[as_of telemetry summaries retention collection].each { |key| assert_includes body.keys, key }
        end

        # Telemetry Tests

        test "reports the span of recorded requests" do
          body = get_coverage
          requests = body["telemetry"]["requests"]

          assert_equal RailsPulse::Request.count, requests["count"]
          assert_operator Time.parse(requests["oldest"]), :<=, Time.parse(requests["newest"])
        end

        test "reports job runs and exceptions alongside requests" do
          body = get_coverage

          %w[requests job_runs exceptions].each { |kind| assert_includes body["telemetry"].keys, kind }
        end

        # An empty error list means nothing was recorded, which only means
        # nothing happened when exceptions were actually being tracked.
        test "says when exceptions are not tracked rather than reporting zero" do
          original = RailsPulse.configuration.track_exceptions
          RailsPulse.configuration.track_exceptions = false

          body = get_coverage

          refute body["telemetry"]["exceptions"]["tracked"]
          assert_includes body["telemetry"]["exceptions"]["reason"], "track_exceptions"
        ensure
          RailsPulse.configuration.track_exceptions = original
        end

        test "says when job runs are not tracked rather than reporting zero" do
          original = RailsPulse.configuration.track_jobs
          RailsPulse.configuration.track_jobs = false

          body = get_coverage

          refute body["telemetry"]["job_runs"]["tracked"]
          assert_includes body["telemetry"]["job_runs"]["reason"], "track_jobs"
        ensure
          RailsPulse.configuration.track_jobs = original
        end

        # Summary Tests

        test "reports how far hourly summaries have been generated" do
          body = get_coverage

          assert_includes body["summaries"].keys, "hourly_through"
          assert_includes body["summaries"].keys, "stale"
        end

        test "flags stale summaries with a reason" do
          RailsPulse::Summary.overall_requests.for_period_type("hour").delete_all

          body = get_coverage

          assert body["summaries"]["stale"]
          assert_includes body["summaries"]["note"], "never run"
        end

        # Retention Tests

        test "reports configured retention in days" do
          body = get_coverage

          assert_in_delta (RailsPulse.configuration.full_retention_period / 86_400.0),
            body["retention"]["raw_records"]["days"]
          assert_in_delta (RailsPulse.configuration.event_retention_period / 86_400.0),
            body["retention"]["events"]["days"]
        end

        # Collection Tests

        test "reports no suspected gap when a writer is beating with no drops" do
          RailsPulse::WriterHeartbeat.events.delete_all
          RailsPulse::WriterHeartbeat.record!(hostname: "web1", pid: 1, queue_size: 100,
            queue_depth: 0, dropped: 0, dropped_total: 0)

          body = get_coverage

          assert_equal 1, body["collection"]["live_writers"]
          refute body["collection"]["gap_suspected"]
          assert_nil body["collection"]["note"]
        end

        test "suspects a gap and explains it when requests were dropped" do
          RailsPulse::WriterHeartbeat.events.delete_all
          RailsPulse::WriterHeartbeat.record!(hostname: "web1", pid: 1, queue_size: 100,
            queue_depth: 100, dropped: 7, dropped_total: 7)

          body = get_coverage

          assert body["collection"]["gap_suspected"]
          assert_equal 7, body["collection"]["dropped_last_hour"]
          assert_includes body["collection"]["note"], "understate"
        end

        # Edge Cases

        # A writer starts with a process's first tracked request, so a quiet
        # writer means nothing was queued, not that anything was lost. An idle
        # app, or one whose only traffic is ignored health checks, must not be
        # reported as losing data.
        test "does not suspect a gap when no writer has reported" do
          RailsPulse::WriterHeartbeat.events.delete_all

          body = get_coverage

          refute body["collection"]["gap_suspected"]
          assert_includes body["collection"]["note"], "no tracked web traffic"
        end

        test "describes a writer that has gone quiet without suspecting a gap" do
          RailsPulse::WriterHeartbeat.events.delete_all
          travel_to 10.minutes.ago do
            RailsPulse::WriterHeartbeat.record!(hostname: "web1", pid: 1, queue_size: 100,
              queue_depth: 0, dropped: 0, dropped_total: 0)
          end

          body = get_coverage

          refute body["collection"]["gap_suspected"]
          assert_equal 0, body["collection"]["live_writers"]
          assert_includes body["collection"]["note"], "no request has been queued since"
        end

        test "does not suspect a gap when requests are written inline" do
          RailsPulse.configuration.async = false
          RailsPulse::WriterHeartbeat.events.delete_all

          body = get_coverage

          refute body["collection"]["gap_suspected"]
          assert_includes body["collection"]["reason"], "config.async is false"
        end

        test "reports nothing recorded rather than failing on an empty table" do
          RailsPulse::Operation.where.not(job_run_id: nil).delete_all
          RailsPulse::JobRun.delete_all

          body = get_coverage

          assert_response :success
          assert_equal 0, body["telemetry"]["job_runs"]["count"]
          assert_nil body["telemetry"]["job_runs"]["newest"]
        end
      end
    end
  end
end
