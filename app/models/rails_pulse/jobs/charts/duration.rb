module RailsPulse
  module Jobs
    module Charts
      class Duration
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

          # Group by period_start and calculate weighted percentiles
          summaries = summaries
            .group(:period_start)
            .select(
              :period_start,
              "SUM(rails_pulse_summaries.count) as total_count",
              "SUM(rails_pulse_summaries.p50_duration * rails_pulse_summaries.count) as total_weighted_p50",
              "SUM(rails_pulse_summaries.p95_duration * rails_pulse_summaries.count) as total_weighted_p95",
              "SUM(rails_pulse_summaries.p99_duration * rails_pulse_summaries.count) as total_weighted_p99"
            )

          # Build raw_data hash from grouped results
          raw_data = {}
          summaries.each do |summary|
            timestamp = summary.period_start.to_i
            count = summary.total_count || 0

            raw_data[timestamp] = {
              total_weighted_p50: summary.total_weighted_p50 || 0,
              total_weighted_p95: summary.total_weighted_p95 || 0,
              total_weighted_p99: summary.total_weighted_p99 || 0,
              total_count: count
            }
          end

          # Convert to final values (weighted averages) and pad missing data
          step = @period_type.to_s == "hour" ? 3600 : 86400
          daily_data = {}
          (@start_time.to_i..@end_time.to_i).step(step) do |timestamp|
            if raw_data[timestamp]
              count = raw_data[timestamp][:total_count]
              daily_data[timestamp] = {
                p50: count > 0 ? (raw_data[timestamp][:total_weighted_p50] / count).round(0) : nil,
                p95: count > 0 ? (raw_data[timestamp][:total_weighted_p95] / count).round(0) : nil,
                p99: count > 0 ? (raw_data[timestamp][:total_weighted_p99] / count).round(0) : nil
              }
            else
              daily_data[timestamp] = { p50: nil, p95: nil, p99: nil }
            end
          end

          # Build labels array (timestamps in milliseconds for JavaScript)
          labels = daily_data.keys.map { |timestamp| timestamp * 1000 }

          # Build series data
          series = []

          p50_data = daily_data.values.map { |data| data[:p50] }
          series << {
            name: "P50",
            data: p50_data,
            type: "line",
            color: RailsPulse::ChartColors::DEFAULT
          }

          p95_data = daily_data.values.map { |data| data[:p95] }
          series << {
            name: "P95",
            data: p95_data,
            type: "line",
            color: RailsPulse::ChartColors::P95
          }

          p99_data = daily_data.values.map { |data| data[:p99] }
          series << {
            name: "P99",
            data: p99_data,
            type: "line",
            color: RailsPulse::ChartColors::P99
          }

          {
            labels: labels,
            series: series
          }
        end
      end
    end
  end
end
