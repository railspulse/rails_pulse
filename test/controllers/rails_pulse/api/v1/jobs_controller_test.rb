require "test_helper"

module RailsPulse
  module Api
    module V1
      class JobsControllerTest < ActionDispatch::IntegrationTest
        VALID_TOKEN = "test-api-token"

        setup do
          RailsPulse.configuration.api_token = VALID_TOKEN
        end

        teardown do
          RailsPulse.configuration.api_token = nil
        end

        test "returns 401 without token" do
          get rails_pulse.api_v1_jobs_path

          assert_response :unauthorized
        end

        test "returns 401 with wrong token" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => "wrong" }

          assert_response :unauthorized
        end

        test "returns 200 with correct token" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }

          assert_response :success
        end

        test "returns expected JSON shape" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert body.key?("data")
          assert body.key?("meta")
          assert_equal %w[total limit offset], body["meta"].keys
        end

        test "serializes job fields" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)
          job = body["data"].first

          %w[id name queue_name runs_count failures_count avg_duration p95_duration p99_duration failure_rate].each do |k|
            assert_includes job.keys, k
          end
        end

        test "meta total reflects all job records" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert_equal RailsPulse::Job.count, body["meta"]["total"]
        end

        test "filters by failed status" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { status: "failed" }
          body = JSON.parse(response.body)

          assert_equal 1, body["data"].length
          body["data"].each { |j| assert_operator j["failures_count"], :>, 0 }
        end

        test "returns 400 for an unknown status" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { status: "slow" }

          assert_response :bad_request
          assert_equal "Invalid status. Valid values: failed", JSON.parse(response.body)["error"]
        end

        test "job filters to one job class by exact name" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { job: "GenerateReportJob" }
          body = JSON.parse(response.body)

          assert_equal [ "GenerateReportJob" ], body["data"].map { |j| j["name"] }
          assert_equal 1, body["meta"]["total"]
        end

        test "job with no match returns an empty page" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { job: "NoSuchJob" }
          body = JSON.parse(response.body)

          assert_empty body["data"]
          assert_equal 0, body["meta"]["total"]
        end

        test "includes failure_rate computed field" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)
          failing = body["data"].find { |j| j["name"] == "GenerateReportJob" }

          assert_in_delta(50.0, failing["failure_rate"])
        end

        test "respects limit parameter" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { limit: 1 }
          body = JSON.parse(response.body)

          assert_equal 1, body["data"].length
        end

        test "respects offset parameter" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: { offset: 1000 }
          body = JSON.parse(response.body)

          assert_empty body["data"]
        end

        # Windowed Statistics
        #
        # The job row's counters are lifetime totals, so a window is answered
        # from the per-job summaries instead. Returning the lifetime numbers
        # would answer a different question without saying so.
        #
        # Bounds come from the fixture rows rather than from `n.hours.ago`,
        # which snaps to a different hour depending on where in the hour the
        # suite happens to run.

        def hourly_job_summaries
          RailsPulse::Summary.for_jobs.for_period_type("hour")
            .where(summarizable_id: rails_pulse_jobs(:report_job).id)
        end

        def window_over_all_hours
          { since: hourly_job_summaries.minimum(:period_start).iso8601,
            until: hourly_job_summaries.maximum(:period_end).iso8601 }
        end

        def window_over_one_hour
          latest = hourly_job_summaries.order(:period_start).last
          { since: latest.period_start.iso8601, until: latest.period_end.iso8601 }
        end

        test "a window is answered from summaries, not the lifetime counters" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: window_over_all_hours
          body = JSON.parse(response.body)
          report = body["data"].find { |j| j["name"] == "GenerateReportJob" }

          assert_equal 140, report["stats"]["runs_count"]
          assert_equal 14, report["stats"]["failures_count"]
          assert_in_delta(10.0, report["stats"]["failure_rate"])
          # Summed duration over summed runs, not the mean of each period's mean.
          assert_in_delta(471.43, report["stats"]["avg_duration"], 0.01)
        end

        test "a window reports the bounds and granularity it read" do
          window = window_over_all_hours
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }, params: window
          body = JSON.parse(response.body)

          assert_equal "hour", body["meta"]["window"]["period_type"]
          assert_operator Time.parse(body["meta"]["window"]["since"]), :<=, Time.parse(window[:since])
          assert_operator Time.parse(body["meta"]["window"]["until"]), :>=, Time.parse(window[:until])
        end

        test "lifetime counters are still returned alongside the window" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: window_over_all_hours
          body = JSON.parse(response.body)
          report = body["data"].find { |j| j["name"] == "GenerateReportJob" }

          assert_equal rails_pulse_jobs(:report_job).runs_count, report["runs_count"]
          refute_equal report["runs_count"], report["stats"]["runs_count"]
        end

        # Percentiles are a property of a distribution, and the distribution
        # behind each period is not kept, so several periods cannot be combined.
        test "percentiles are reported when one period covers the window" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: window_over_one_hour
          body = JSON.parse(response.body)
          report = body["data"].find { |j| j["name"] == "GenerateReportJob" }

          assert_in_delta(800.0, report["stats"]["p95_duration"])
          assert_in_delta(880.0, report["stats"]["p99_duration"])
          refute_includes report["stats"].keys, "percentiles_note"
        end

        test "percentiles are withheld with a reason across several periods" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: window_over_all_hours
          body = JSON.parse(response.body)
          report = body["data"].find { |j| j["name"] == "GenerateReportJob" }

          refute_includes report["stats"].keys, "p95_duration"
          assert_includes report["stats"]["percentiles_note"], "cannot be combined"
        end

        test "a window with no summaries returns no rows rather than lifetime totals" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: { since: "2099-01-01T00:00:00Z", until: "2099-01-02T00:00:00Z" }
          body = JSON.parse(response.body)

          assert_empty body["data"]
          assert_equal 0, body["meta"]["total"]
        end

        # Hourly summaries are pruned before daily ones, so a window older than
        # hourly retention is answered from daily rows rather than reported as
        # empty.
        test "a window older than hourly retention falls back to daily summaries" do
          # Retention has removed the hourly rows for that window; only the
          # daily ones are left to answer from.
          RailsPulse::Summary.for_jobs.for_period_type("hour").delete_all
          daily = RailsPulse::Summary.for_jobs.for_period_type("day")
            .where(summarizable_id: rails_pulse_jobs(:report_job).id).order(:period_start).last

          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN },
            params: { since: daily.period_start.iso8601, until: daily.period_end.iso8601 }
          body = JSON.parse(response.body)
          report = body["data"].find { |j| j["name"] == "GenerateReportJob" }

          assert_equal "day", body["meta"]["window"]["period_type"]
          assert_equal 200, report["stats"]["runs_count"]
        end

        test "without a window the counters stay lifetime totals and stats is absent" do
          get rails_pulse.api_v1_jobs_path, headers: { "X-Rails-Pulse-Token" => VALID_TOKEN }
          body = JSON.parse(response.body)

          assert_nil body["data"].first["stats"]
          refute_includes body["meta"].keys, "window"
        end
      end
    end
  end
end
