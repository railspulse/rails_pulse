module RailsPulse
  module Mcp
    module Tools
      class Jobs < ::MCP::Tool
        extend Helpers

        ERROR_MESSAGE_LENGTH = 200

        # Failed runs fetched for recent_failures. The count reported beside
        # them is the API's total, not the size of this sample.
        FAILED_RUN_SAMPLE = 100

        tool_name "rails_pulse_jobs"
        description "Background job health: failure rates, slow jobs, and recent failures with error classes. " \
                    "Use this to find failing or slow background jobs."

        annotations(
          read_only_hint: true,
          destructive_hint: false,
          open_world_hint: false
        )

        input_schema(
          properties: {
            **Helpers.window_properties("last_24_hours"),
            limit: {
              type: "integer",
              description: "Maximum number of jobs to return (1-50)",
              default: 10
            },
            job: {
              type: "string",
              description: "Restrict to one job class (e.g. 'GenerateReportJob')"
            }
          }
        )

        def self.call(period: "last_24_hours", limit: 10, job: nil, server_context:, **options)
          respond(server_context) do |client|
            window = resolve_window(period: period, since: options[:since], until_time: options[:until])
            limit = limit.to_i.clamp(1, 50)

            # Windowed: the API answers these from summaries so the counts and
            # durations cover the same period as recent_failures. Every job is
            # fetched because the API orders by name and the ranking here is
            # by failure rate; a first page would drop the worst after the
            # alphabet ran past it.
            job_params = window_params(window)
            job_params[:job] = job if job
            jobs, result = fetch_all(client, "/jobs", job_params)
            granularity = result.dig("meta", "window", "period_type")

            run_params = window_params(window).merge(status: "failed", limit: FAILED_RUN_SAMPLE)
            run_params[:job] = job if job
            runs_result = client.get("/job_runs", run_params)
            failed_runs = runs_result["data"] || []
            failed_total = runs_result.dig("meta", "total") || failed_runs.size

            formatted = jobs.map { |j| format_job(j) }
              .sort_by { |j| [ -j[:failure_rate].to_f, -slowness(j) ] }
              .first(limit)

            payload = {
              window: window.merge(granularity ? { summary_period: granularity } : {}),
              jobs: formatted,
              failed_runs: failed_total,
              recent_failures: format_failures(failed_runs),
              summary: build_summary(formatted, jobs.size, failed_total, failed_runs.size),
              next_steps: build_next_steps(formatted, failed_runs)
            }
            note = formatted.filter_map { |j| j[:percentiles_note] }.first
            payload[:note] = note if note
            payload
          end
        end

        # The tool always asks for a window, so every figure comes from the
        # window's `stats`. The job's lifetime counters are never substituted:
        # a withheld percentile stays nil rather than becoming an all-time one.
        private_class_method def self.format_job(job)
          stats = job["stats"] || {}
          formatted = {
            name: job["name"],
            queue: job["queue_name"],
            runs: stats["runs_count"].to_i,
            failures: stats["failures_count"].to_i,
            failure_rate: stats["failure_rate"].to_f.round(1),
            avg_ms: stats["avg_duration"]&.to_f&.round(1),
            max_ms: stats["max_duration"]&.to_f&.round(1),
            p95_ms: stats["p95_duration"]&.to_f&.round(1),
            p99_ms: stats["p99_duration"]&.to_f&.round(1)
          }
          formatted[:percentiles_note] = stats["percentiles_note"] if stats["percentiles_note"]
          formatted
        end

        # p95 when the window has one, otherwise the mean.
        private_class_method def self.slowness(job)
          (job[:p95_ms] || job[:avg_ms]).to_f
        end

        private_class_method def self.format_failures(runs)
          runs.group_by { |r| r["job_name"] || "unknown" }.map do |name, group|
            latest = group.max_by { |r| r["occurred_at"].to_s }
            {
              job: name,
              count: group.size,
              error_classes: group.map { |r| r["error_class"] || "unknown" }.tally,
              latest: {
                occurred_at: latest["occurred_at"],
                error_class: latest["error_class"],
                error_message: truncate(latest["error_message"], ERROR_MESSAGE_LENGTH),
                attempts: latest["attempts"]
              }
            }
          end.sort_by { |f| -f[:count] }
        end

        private_class_method def self.build_summary(jobs, job_total, failed_total, failed_sampled)
          return "No background jobs recorded." if jobs.empty?

          failed = "#{failed_total} failed run(s) in period"
          failed += " (latest #{failed_sampled} grouped in recent_failures)" if failed_total > failed_sampled
          parts = [ "#{job_total} job(s) ran, #{failed}" ]
          worst = jobs.max_by { |j| j[:failure_rate] }
          parts << "Highest failure rate: #{worst[:name]} (#{worst[:failure_rate]}%)" if worst[:failure_rate] > 0
          slowest = jobs.max_by { |j| slowness(j) }
          if slowest
            label = slowest[:p95_ms] ? "p95 #{slowest[:p95_ms]}ms" : "avg #{slowest[:avg_ms]}ms"
            parts << "Slowest: #{slowest[:name]} (#{label})"
          end
          parts.join(". ") + "."
        end

        private_class_method def self.build_next_steps(jobs, failed_runs)
          steps = []
          if jobs.empty?
            steps << "No jobs tracked — confirm `config.track_jobs` is enabled in the Rails Pulse initializer."
          end
          if failed_runs.any?
            steps << "Group failures by error_class in recent_failures; a single class dominating usually points at one root cause."
          end
          if jobs.any? { |j| j[:failure_rate] > 5 }
            steps << "Jobs with failure rate above 5% need retry/discard handling reviewed."
          end
          if jobs.any? { |j| slowness(j) > 60_000 }
            steps << "Jobs taking over 60s (p95, or the mean where no p95 is given) may be blocking queues — consider splitting or batching."
          end
          steps << "Use rails_pulse_queries to check whether slow jobs are dominated by SQL."
          steps
        end
      end
    end
  end
end
