module RailsPulse
  module Routes
    module Charts
      class ClientErrorRate
        def initialize(ransack_query:, period_type: nil, route: nil, start_time: nil, end_time: nil, start_duration: nil, disabled_tags: [], show_non_tagged: true)
          @ransack_query = ransack_query
          @period_type = period_type
          @route = route
          @start_time = start_time
          @end_time = end_time
          @start_duration = start_duration
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_chart_data
          summaries = @ransack_query.result(distinct: false)
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: @period_type
            )

          summaries = summaries.where(summarizable_id: @route.id) if @route

          # Group by period_start and calculate client error rate
          summaries = summaries
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
          step = @period_type.to_s == "hour" ? 3600 : 86400
          daily_data = {}
          (@start_time.to_i..@end_time.to_i).step(step) do |timestamp|
            daily_data[timestamp] = raw_data[timestamp] || 0
          end

          # Build labels array (timestamps in milliseconds for JavaScript)
          labels = daily_data.keys.map { |timestamp| timestamp * 1000 }

          # Build series data
          series = [{
            name: "Client Error Rate",
            data: daily_data.values,
            type: "line",
            color: RailsPulse::ChartColors::P99
          }]

          {
            labels: labels,
            series: series
          }
        end
      end
    end
  end
end
