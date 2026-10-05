module RailsPulse
  module Dashboard
    module Concerns
      # How a route, query or job earns a place in a needs-attention list,
      # shared by the dashboard panel (NeedsAttention, over the selected
      # window) and the API's PeriodInsights (over one summary period) so the
      # two never disagree about what is critical.
      #
      # Each classify method returns nil for something healthy, otherwise
      # [severity, reason, metric, metric_sub, sort_score]. The includer sets
      # @route_thresholds, @query_thresholds and @job_thresholds.
      module AttentionClassification
        include ThresholdConstants

        private

        # `span` finishes the error-rate reason: "this week", "this period".
        def classify_route(p95, total, errors, error_rate, span)
          if p95 >= @route_thresholds[:critical] || error_rate >= CRITICAL_ERROR_RATE
            if error_rate >= CRITICAL_ERROR_RATE
              [ :critical,
                "#{error_rate}% error rate · #{total} requests #{span}",
                "#{errors} errors",
                "P95 #{p95.round(0).to_i}ms",
                errors * total.to_f ]
            else
              [ :critical,
                "#{p95.round(0).to_i}ms P95 · exceeds #{@route_thresholds[:critical]}ms threshold",
                "#{p95.round(0).to_i}ms P95",
                "#{total} requests",
                p95 ]
            end
          elsif p95 >= @route_thresholds[:slow] || error_rate >= WARNING_ERROR_RATE
            if error_rate >= WARNING_ERROR_RATE && p95 < @route_thresholds[:slow]
              [ :warning,
                "#{error_rate}% error rate · #{total} requests #{span}",
                "#{errors} errors",
                "P95 #{p95.round(0).to_i}ms",
                errors * total.to_f ]
            else
              [ :warning,
                "#{p95.round(0).to_i}ms P95 · #{error_rate > 0 ? "#{error_rate}% error rate" : "above slow threshold"}",
                "#{p95.round(0).to_i}ms P95",
                "#{total} requests",
                p95 ]
            end
          end
        end

        def classify_query(p95, count)
          if p95 >= @query_thresholds[:critical]
            severity = :critical
            reason   = "#{p95.round(0).to_i}ms P95 · exceeds #{@query_thresholds[:critical]}ms threshold"
          elsif p95 >= @query_thresholds[:slow]
            severity = :warning
            reason   = "#{p95.round(0).to_i}ms P95 · above #{@query_thresholds[:slow]}ms slow threshold"
          else
            return
          end

          [ severity, reason, "#{p95.round(0).to_i}ms P95", "#{count} execution#{count == 1 ? "" : "s"}", p95 ]
        end

        def classify_job(failure_rate, p95, runs, failures, queue)
          if failure_rate >= CRITICAL_JOB_FAILURE_RATE || p95 >= @job_thresholds[:critical]
            if failure_rate >= CRITICAL_JOB_FAILURE_RATE
              [ :critical,
                "#{queue} queue · #{failure_rate}% failure rate",
                "#{failures} / #{runs} failed",
                "P95 #{p95.round(0).to_i}ms",
                failures * runs.to_f ]
            else
              [ :critical,
                "P95 #{p95.round(0).to_i}ms · exceeds #{@job_thresholds[:critical]}ms threshold",
                "#{p95.round(0).to_i}ms P95",
                "#{runs} runs",
                p95 ]
            end
          elsif failure_rate >= WARNING_JOB_FAILURE_RATE || p95 >= @job_thresholds[:slow]
            if failure_rate >= WARNING_JOB_FAILURE_RATE
              [ :warning,
                "#{queue} queue · #{failure_rate}% failure rate",
                "#{failures} / #{runs} failed",
                "P95 #{p95.round(0).to_i}ms",
                failures * runs.to_f ]
            else
              [ :warning,
                "P95 #{p95.round(0).to_i}ms · above slow threshold",
                "#{p95.round(0).to_i}ms P95",
                "#{runs} runs",
                p95 ]
            end
          end
        end

        def truncate_sql(sql)
          return "" if sql.blank?
          cleaned = sql.gsub(/\s+/, " ").strip
          cleaned.length > 80 ? "#{cleaned[0..79]}..." : cleaned
        end
      end
    end
  end
end
