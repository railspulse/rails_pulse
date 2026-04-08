module RailsPulse
  module Routes
    module Charts
      class ClientErrorRate < RailsPulse::Charts::Base
        def initialize(route: nil, **kwargs)
          super(subject: route, **kwargs)
        end

        def to_chart_data
          summaries = base_summary_query
            .group(:period_start)
            .select(
              :period_start,
              "SUM(count) as total_count",
              "SUM(status_4xx) as total_4xx"
            )

          # Build raw_data hash from grouped results
          raw_data = {}
          summaries.each do |summary|
            timestamp = summary.period_start.to_i
            count = summary.total_count || 0
            errors_4xx = summary.total_4xx || 0

            # Calculate client error rate as percentage
            raw_data[timestamp] = count > 0 ? (errors_4xx.to_f / count * 100).round(2) : 0
          end

          # Pad missing data with zeros
          daily_data = pad_data_with_zeros(raw_data, @start_time, @end_time, time_step)

          # Build labels array (timestamps in milliseconds for JavaScript)
          labels = daily_data.keys.map { |timestamp| timestamp * 1000 }

          # Build series data
          series = [ {
            name: "Client Error Rate",
            data: daily_data.values,
            type: "line",
            color: RailsPulse::ChartColors::P99
          } ]

          {
            labels: labels,
            series: series
          }
        end

        private

        def summarizable_type = "RailsPulse::Route"
      end
    end
  end
end
