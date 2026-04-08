module RailsPulse
  module Jobs
    module Charts
      class ExecutionVolume < Base
        def to_chart_data
          summaries = base_summary_query

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
          step = time_step
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
