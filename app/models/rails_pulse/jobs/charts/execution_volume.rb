module RailsPulse
  module Jobs
    module Charts
      class ExecutionVolume
        def initialize(ransack_query:, period_type: nil, job: nil, start_time: nil, end_time: nil, start_duration: nil, disabled_tags: [], show_non_tagged: true)
          @ransack_query = ransack_query
          @period_type = period_type
          @job = job
          @start_time = start_time
          @end_time = end_time
          @start_duration = start_duration
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_chart_data
          summaries = @ransack_query.result(distinct: false)
            .joins("INNER JOIN rails_pulse_jobs ON rails_pulse_jobs.id = rails_pulse_summaries.summarizable_id")
            .where(
              summarizable_type: "RailsPulse::Job",
              period_type: @period_type
            )

          # Apply tag filters
          actual_disabled_tags = @disabled_tags.reject { |tag| tag == "non_tagged" }
          actual_disabled_tags.each do |tag|
            sanitized_tag = ActiveRecord::Base.sanitize_sql_like(tag.to_s, "\\")
            summaries = summaries.where.not("rails_pulse_jobs.tags LIKE ?", "%#{sanitized_tag}%")
          end

          unless @show_non_tagged
            summaries = summaries.where("rails_pulse_jobs.tags IS NOT NULL AND rails_pulse_jobs.tags != '[]'")
          end

          summaries = summaries.where(summarizable_id: @job.id) if @job

          # Group by period_start and sum execution counts
          summaries = summaries
            .group(:period_start)
            .select(
              :period_start,
              "SUM(rails_pulse_summaries.count) as total_count"
            )

          # Build raw_data hash from grouped results
          raw_data = {}
          summaries.each do |summary|
            timestamp = summary.period_start.to_i
            raw_data[timestamp] = summary.total_count || 0
          end

          # Pad missing data with zeros
          step = @period_type.to_s == "hour" ? 3600 : 86400
          daily_data = {}
          (@start_time.to_i..@end_time.to_i).step(step) do |timestamp|
            daily_data[timestamp] = raw_data[timestamp] || 0
          end

          # Build labels array (timestamps in milliseconds for JavaScript)
          labels = daily_data.keys.map { |timestamp| timestamp * 1000 }

          # Build series data
          series = [ {
            name: "Executions",
            data: daily_data.values,
            type: "bar",
            color: RailsPulse::ChartColors::DEFAULT
          } ]

          {
            labels: labels,
            series: series
          }
        end
      end
    end
  end
end
