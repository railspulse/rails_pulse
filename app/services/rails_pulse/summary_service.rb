
module RailsPulse
  class SummaryService
    attr_reader :period_type, :start_time, :end_time

    def initialize(period_type, start_time)
      @period_type = period_type
      @start_time = Summary.normalize_period_start(period_type, start_time)
      @end_time = Summary.calculate_period_end(period_type, @start_time)
    end

    def perform
      Rails.logger.info "[RailsPulse] Starting #{period_type} summary for #{start_time}"

      ActiveRecord::Base.transaction do
        aggregate_requests  # Overall system metrics
        aggregate_routes    # Per-route metrics
        aggregate_queries   # Per-query metrics
        aggregate_jobs      # Per-job metrics
      end

      Rails.logger.info "[RailsPulse] Completed #{period_type} summary"
    rescue => e
      Rails.logger.error "[RailsPulse] Summary failed: #{e.message}"
      raise
    end

    private

    def aggregate_requests
      # Create a single summary for ALL requests in this period
      requests = Request.where(occurred_at: start_time...end_time)

      return if requests.empty?

      # Get all durations and statuses for percentile calculations
      request_data = requests.pluck(:duration, :status)
      durations = request_data.map(&:first).compact.sort
      statuses = request_data.map(&:second)

      # Find or create the overall request summary
      summary = Summary.find_or_initialize_by(
        summarizable_type: "RailsPulse::Request",
        summarizable_id: 0,  # Use 0 as a special ID for overall summaries
        period_type: period_type,
        period_start: start_time
      )

      summary.assign_attributes(
        period_end: end_time,
        count: durations.size,
        avg_duration: durations.any? ? durations.sum.to_f / durations.size : 0,
        min_duration: durations.min,
        max_duration: durations.max,
        total_duration: durations.sum,
        p50_duration: calculate_percentile(durations, 0.5),
        p95_duration: calculate_percentile(durations, 0.95),
        p99_duration: calculate_percentile(durations, 0.99),
        stddev_duration: calculate_stddev(durations, durations.sum.to_f / durations.size),
        error_count: statuses.count { |s| s >= 400 },
        success_count: statuses.count { |s| s < 400 },
        status_2xx: statuses.count { |s| s.between?(200, 299) },
        status_3xx: statuses.count { |s| s.between?(300, 399) },
        status_4xx: statuses.count { |s| s.between?(400, 499) },
        status_5xx: statuses.count { |s| s >= 500 }
      )

      summary.save!
    end

    private

    def aggregate_routes
      # Use ActiveRecord for cross-database compatibility
      route_groups = Request
        .where(occurred_at: start_time...end_time)
        .where.not(route_id: nil)
        .joins(:route)
        .group(:route_id)

      # Calculate basic aggregates
      basic_stats = route_groups.pluck(
        :route_id,
        Arel.sql("COUNT(*) as request_count"),
        Arel.sql("AVG(duration) as avg_duration"),
        Arel.sql("MIN(duration) as min_duration"),
        Arel.sql("MAX(duration) as max_duration"),
        Arel.sql("SUM(duration) as total_duration")
      )

      basic_stats.each do |stats|
        route_id = stats[0]

        # Calculate percentiles and status counts separately for cross-DB compatibility
        durations = Request
          .where(occurred_at: start_time...end_time)
          .where(route_id: route_id)
          .pluck(:duration, :status)

        sorted_durations = durations.map(&:first).compact.sort
        statuses = durations.map(&:last)

        summary = Summary.find_or_initialize_by(
          summarizable_type: "RailsPulse::Route",
          summarizable_id: route_id,
          period_type: period_type,
          period_start: start_time
        )

        summary.assign_attributes(
          period_end: end_time,
          count: stats[1],
          avg_duration: stats[2],
          min_duration: stats[3],
          max_duration: stats[4],
          total_duration: stats[5],
          p50_duration: calculate_percentile(sorted_durations, 0.5),
          p95_duration: calculate_percentile(sorted_durations, 0.95),
          p99_duration: calculate_percentile(sorted_durations, 0.99),
          stddev_duration: calculate_stddev(sorted_durations, stats[2]),
          error_count: statuses.count { |s| s >= 400 },
          success_count: statuses.count { |s| s < 400 },
          status_2xx: statuses.count { |s| s.between?(200, 299) },
          status_3xx: statuses.count { |s| s.between?(300, 399) },
          status_4xx: statuses.count { |s| s.between?(400, 499) },
          status_5xx: statuses.count { |s| s >= 500 }
        )

        summary.save!
      end
    end

    def aggregate_queries
      query_groups = Operation
        .where(occurred_at: start_time...end_time)
        .where.not(query_id: nil)
        .joins(:query)
        .group(:query_id)

      basic_stats = query_groups.pluck(
        :query_id,
        Arel.sql("COUNT(*) as execution_count"),
        Arel.sql("AVG(duration) as avg_duration"),
        Arel.sql("MIN(duration) as min_duration"),
        Arel.sql("MAX(duration) as max_duration"),
        Arel.sql("SUM(duration) as total_duration")
      )

      basic_stats.each do |stats|
        query_id = stats[0]

        # Calculate percentiles separately
        durations = Operation
          .where(occurred_at: start_time...end_time)
          .where(query_id: query_id)
          .pluck(:duration)
          .compact
          .sort

        summary = Summary.find_or_initialize_by(
          summarizable_type: "RailsPulse::Query",
          summarizable_id: query_id,
          period_type: period_type,
          period_start: start_time
        )

        summary.assign_attributes(
          period_end: end_time,
          count: stats[1],
          avg_duration: stats[2],
          min_duration: stats[3],
          max_duration: stats[4],
          total_duration: stats[5],
          p50_duration: calculate_percentile(durations, 0.5),
          p95_duration: calculate_percentile(durations, 0.95),
          p99_duration: calculate_percentile(durations, 0.99),
          stddev_duration: calculate_stddev(durations, stats[2])
        )

        summary.save!
      end
    end

    def aggregate_jobs
      job_runs = JobRun
        .includes(:job)
        .where(occurred_at: start_time...end_time)
        .where(status: JobRun::FINAL_STATUSES)

      return if job_runs.empty?

      job_runs.group_by(&:job_id).each do |job_id, runs|
        job = runs.first&.job
        next unless job

        duration_values = runs.map(&:duration).compact.map(&:to_f).sort
        next if duration_values.empty?

        duration_count = duration_values.size
        total_duration = duration_values.sum
        average_duration = total_duration / duration_count

        summary = Summary.find_or_initialize_by(
          summarizable_type: "RailsPulse::Job",
          summarizable_id: job.id,
          period_type: period_type,
          period_start: start_time
        )

        summary.assign_attributes(
          period_end: end_time,
          count: runs.size,
          avg_duration: average_duration,
          min_duration: duration_values.first,
          max_duration: duration_values.last,
          total_duration: total_duration,
          p50_duration: calculate_percentile(duration_values, 0.5),
          p95_duration: calculate_percentile(duration_values, 0.95),
          p99_duration: calculate_percentile(duration_values, 0.99),
          stddev_duration: calculate_stddev(duration_values, average_duration),
          error_count: runs.count(&:failure_like_status?),
          success_count: runs.count { |run| run.status == "success" }
        )

        summary.save!
      end
    end

    def calculate_percentile(sorted_array, percentile)
      return nil if sorted_array.empty?

      k = (percentile * (sorted_array.length - 1)).floor
      f = (percentile * (sorted_array.length - 1)) - k

      return sorted_array[k] if f == 0 || k + 1 >= sorted_array.length

      sorted_array[k] + (sorted_array[k + 1] - sorted_array[k]) * f
    end

    def calculate_stddev(values, mean)
      return nil if values.empty? || values.size == 1

      sum_of_squares = values.sum { |v| (v - mean) ** 2 }
      Math.sqrt(sum_of_squares / (values.size - 1))
    end
  end
end
