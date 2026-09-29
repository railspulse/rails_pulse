module RailsPulse
  module Api
    module V1
      class JobSerializer
        # Without `stats` the counters are the job's lifetime totals, cached on
        # the row. With it they cover one window and come from summaries, so
        # the two are kept in separate keys rather than one set of names
        # meaning different things depending on the request.
        def self.serialize(job, stats: nil)
          {
            id:             job.id,
            name:           job.name,
            queue_name:     job.queue_name,
            runs_count:     job.runs_count,
            failures_count: job.failures_count,
            avg_duration:   job.avg_duration,
            p95_duration:   job.p95_duration,
            p99_duration:   job.p99_duration,
            failure_rate:   job.failure_rate,
            stats:          stats
          }
        end
      end
    end
  end
end
