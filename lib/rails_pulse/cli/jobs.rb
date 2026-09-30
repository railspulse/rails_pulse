require_relative "base_command"
require_relative "formatter"

module RailsPulse
  module CLI
    class Jobs < BaseCommand
      COLUMNS = [
        [ "Name",     35, :name ],
        [ "Queue",    15, :queue_name ],
        [ "Runs",      8, :runs_count ],
        [ "Failures",  8, :failures_count ],
        [ "Fail %",    8, :failure_rate ],
        [ "Avg (ms)", 10, :avg_duration ]
      ].freeze

      # With a window each row's figures cover it, read from summaries.
      WINDOW_COLUMNS = [
        [ "Name",     35, :name ],
        [ "Queue",    15, :queue_name ],
        [ "Runs",      8, :runs_count ],
        [ "Failures",  8, :failures_count ],
        [ "Fail %",    8, :failure_rate ],
        [ "Avg (ms)", 10, :avg_duration ],
        [ "Max (ms)", 10, :max_duration ]
      ].freeze

      desc "list", "List background jobs with run counts and duration stats"
      long_desc <<~DESC
        Returns all tracked background jobs ordered by name.

        Without a window each row shows lifetime stats: total runs, failure count,
        failure rate (%), and average duration in milliseconds.

        With --since and/or --until (ISO 8601) each row covers that window instead,
        and only jobs that ran in it are listed. p95 and p99 appear in --json output
        when one summary period covers the window:
          --since 2026-06-01T00:00:00Z --until 2026-06-02T00:00:00Z

        Filter to jobs that have failed (inside the window, when one is given):
          --status failed

        Restrict to one job class:
          --job GenerateReportJob

        Use --json to also see p95 and p99 duration percentiles and meta.window.
      DESC
      option :limit,  type: :numeric, default: 25,    desc: "Max records to return (1–500)"
      option :offset, type: :numeric, default: 0,     desc: "Number of records to skip (for pagination)"
      option :since,  type: :string,                  desc: "Window start (ISO 8601); rows then cover the window"
      option :until,  type: :string,                  desc: "Window end (ISO 8601)"
      option :job,    type: :string,                  desc: "Exact job class name"
      option :status, type: :string,                  desc: "Filter by status — 'failed' returns only jobs with failures"
      option :json,   type: :boolean, default: false, desc: "Output raw JSON including meta envelope and p95/p99 durations"
      def list
        with_error_handling do
          params = { limit: options[:limit], offset: options[:offset] }
          %i[status since until job].each { |key| params[key] = options[key] if options[key] }
          result = client.get("/jobs", params)

          # JSON keeps lifetime counters and the window's stats apart, as the
          # API does; the table shows whichever the rows describe.
          next Formatter.render(result, json: true) if options[:json]

          windowed = result["data"].any? { |job| job["stats"] }
          rows = result["data"].map { |job| job.merge(job["stats"] || {}) }
          Formatter.render(result.merge("data" => rows), columns: windowed ? WINDOW_COLUMNS : COLUMNS)
        end
      end
    end
  end
end
