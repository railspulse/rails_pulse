module RailsPulse
  module Seeds
    module JobSummaries
      def self.seed!(jobs)
        print "Generating job summaries"

        historical_count = aggregate_from_runs(jobs)
        synthetic_count = create_synthetic_summaries(jobs)

        puts "\nCreated #{historical_count + synthetic_count} summaries (#{historical_count} from runs, #{synthetic_count} synthetic)"
      end

      private

      def self.aggregate_from_runs(jobs)
        ::RailsPulse::Summary.where(summarizable_type: "RailsPulse::Job").delete_all

        summary_periods = %w[hour day week]
        summary_count = 0

        jobs.each do |job|
          runs = job.runs.where(status: ::RailsPulse::JobRun::FINAL_STATUSES).to_a
          next if runs.empty?

          summary_periods.each do |period_type|
            runs.group_by { |run| ::RailsPulse::Summary.normalize_period_start(period_type, run.occurred_at) }.each do |period_start, grouped_runs|
              durations = grouped_runs.map(&:duration).compact.map(&:to_f).sort
              next if durations.empty?

              average_duration = durations.sum / durations.size

              summary = ::RailsPulse::Summary.find_or_initialize_by(
                summarizable: job,
                period_type: period_type,
                period_start: period_start
              )

              summary.assign_attributes(
                period_end: ::RailsPulse::Summary.calculate_period_end(period_type, period_start),
                count: grouped_runs.size,
                avg_duration: average_duration,
                min_duration: durations.first,
                max_duration: durations.last,
                total_duration: durations.sum,
                p50_duration: SeedHelpers.percentile(durations, 0.5),
                p95_duration: SeedHelpers.percentile(durations, 0.95),
                p99_duration: SeedHelpers.percentile(durations, 0.99),
                stddev_duration: SeedHelpers.stddev(durations, average_duration),
                error_count: grouped_runs.count { |run| run.failure_like_status? },
                success_count: grouped_runs.count { |run| run.status == "success" }
              )

              summary.save!
              summary_count += 1
            end
          end

          print "." if summary_count % 20 == 0
        end

        summary_count
      end

      def self.create_synthetic_summaries(jobs)
        job_definitions = BackgroundJobs::JOB_DEFINITIONS.index_by { |defn| defn[:name] }
        synthetic_count = 0

        recent_days = (0..7).map { |offset| offset.days.ago.beginning_of_day }

        jobs.each do |job|
          job_def = job_definitions[job.name]
          next unless job_def

          recent_days.each do |period_start|
            summary = ::RailsPulse::Summary.find_or_initialize_by(
              summarizable: job,
              period_type: "day",
              period_start: period_start
            )

            next if summary.persisted?

            run_count = [ (job_def[:runs_per_day] * 0.15).round, 1 ].max
            durations = Array.new(run_count) do
              value = job_def[:base_duration] + rand(-job_def[:variance]..job_def[:variance])
              [ value, 10 ].max.to_f
            end.sort

            average_duration = durations.sum / durations.size
            error_estimate = [ (durations.size * job_def[:error_rate]).round, durations.size ].min
            success_estimate = durations.size - error_estimate

            summary.assign_attributes(
              period_end: ::RailsPulse::Summary.calculate_period_end("day", period_start),
              count: durations.size,
              avg_duration: average_duration,
              min_duration: durations.first,
              max_duration: durations.last,
              total_duration: durations.sum,
              p50_duration: SeedHelpers.percentile(durations, 0.5),
              p95_duration: SeedHelpers.percentile(durations, 0.95),
              p99_duration: SeedHelpers.percentile(durations, 0.99),
              stddev_duration: SeedHelpers.stddev(durations, average_duration),
              error_count: error_estimate,
              success_count: success_estimate
            )

            summary.save!
            synthetic_count += 1
          end
        end

        synthetic_count
      end
    end
  end
end
