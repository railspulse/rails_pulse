module RailsPulse
  module Routes
    module Charts
      class ResponseTimePercentiles
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

          # Group by period_start at database level and calculate aggregates
          # This aggregates all routes' data for each time period
          summaries = summaries
            .group(:period_start)
            .select(
              :period_start,
              "SUM(count) as total_count",
              "SUM(p95_duration * count) as total_weighted_p95",
              "SUM(p99_duration * count) as total_weighted_p99"
            )

          # Build raw_data hash from grouped results
          raw_data = {}
          summaries.each do |summary|
            timestamp = summary.period_start.to_i
            count = summary.total_count || 0

            raw_data[timestamp] = {
              total_weighted_p95: summary.total_weighted_p95 || 0,
              total_weighted_p99: summary.total_weighted_p99 || 0,
              total_count: count
            }
          end

          # Convert to final values (weighted averages) and pad missing data
          step = @period_type == :hour ? 3600 : 86400
          daily_data = {}
          (@start_time.to_i..@end_time.to_i).step(step) do |timestamp|
            if raw_data[timestamp]
              count = raw_data[timestamp][:total_count]
              daily_data[timestamp] = {
                p95: count > 0 ? (raw_data[timestamp][:total_weighted_p95] / count).round(0) : 0,
                p99: count > 0 ? (raw_data[timestamp][:total_weighted_p99] / count).round(0) : 0
              }
            else
              daily_data[timestamp] = { p95: 0, p99: 0 }
            end
          end

          # Build labels array (timestamps in milliseconds for JavaScript)
          labels = daily_data.keys.map { |timestamp| timestamp * 1000 }

          # Build series data
          series = []

          # Add P95 series (green)
          p95_data = daily_data.values.map { |data| data[:p95] }
          series << {
            name: "P95",
            data: p95_data,
            type: "line",
            color: "#10b981"  # green
          }

          # Add P99 series (blue)
          p99_data = daily_data.values.map { |data| data[:p99] }
          series << {
            name: "P99",
            data: p99_data,
            type: "line",
            color: "#3b82f6"  # blue
          }

          # Add Service Level Objective series if configured
          slo_config = RailsPulse.configuration.service_level_objective
          if slo_config
            slo_data = Array.new(labels.length, slo_config[:threshold])
            series.unshift({
              name: "Service Level Objective (#{slo_config[:threshold]}ms)",
              data: slo_data,
              type: "line",
              lineStyle: { type: "dashed", width: 2 },
              color: "#ef4444",
              symbol: "none"
            })
          end

          {
            labels: labels,
            series: series
          }
        end
      end
    end
  end
end
