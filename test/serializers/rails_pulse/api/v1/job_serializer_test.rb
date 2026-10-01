require "test_helper"

module RailsPulse
  module Api
    module V1
      class JobSerializerTest < ActiveSupport::TestCase
        test "serializes all expected fields" do
          job = rails_pulse_jobs(:mailer_job)
          result = JobSerializer.serialize(job)

          assert_equal job.id,             result[:id]
          assert_equal job.name,           result[:name]
          assert_equal job.queue_name,     result[:queue_name]
          assert_equal job.runs_count,     result[:runs_count]
          assert_equal job.failures_count, result[:failures_count]
          assert_equal job.avg_duration,   result[:avg_duration]
          assert_nil result[:p95_duration]
          assert_nil result[:p99_duration]
          assert_equal job.failure_rate,   result[:failure_rate]
        end

        test "returns a hash with exactly the expected keys" do
          result = JobSerializer.serialize(rails_pulse_jobs(:mailer_job))

          assert_equal %i[id name queue_name runs_count failures_count avg_duration p95_duration p99_duration failure_rate stats], result.keys
        end

        test "stats is nil unless a window was requested" do
          result = JobSerializer.serialize(rails_pulse_jobs(:mailer_job))

          assert_nil result[:stats]
        end

        # The top-level counters stay the job's lifetime totals so a caller
        # reading them does not silently get a window's numbers instead.
        test "window stats are carried beside the lifetime counters, not in place of them" do
          job = rails_pulse_jobs(:mailer_job)
          result = JobSerializer.serialize(job, stats: { runs_count: 3 })

          assert_equal 3, result[:stats][:runs_count]
          assert_equal job.runs_count, result[:runs_count]
        end
      end
    end
  end
end
