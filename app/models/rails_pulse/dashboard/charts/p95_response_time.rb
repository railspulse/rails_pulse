module RailsPulse
  module Dashboard
    module Charts
      class P95ResponseTime
        def initialize(disabled_tags: [], show_non_tagged: true)
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_chart_data
          # Create a range of all dates in the past 2 weeks
          start_date = 2.weeks.ago.beginning_of_day.to_date
          end_date = Time.current.to_date
          date_range = (start_date..end_date)

          # Get the actual data from Summary records (queries for P95 and P99)
          summaries = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Query",
              period_type: "day",
              period_start: start_date.beginning_of_day..end_date.end_of_day
            )

          # Group by day and calculate weighted percentiles
          daily_data = {}
          summaries.each do |summary|
            date = summary.period_start.to_date
            count = summary.count || 0

            if daily_data[date]
              daily_data[date][:total_weighted_p95] += (summary.p95_duration || 0) * count
              daily_data[date][:total_weighted_p99] += (summary.p99_duration || 0) * count
              daily_data[date][:total_count] += count
            else
              daily_data[date] = {
                total_weighted_p95: (summary.p95_duration || 0) * count,
                total_weighted_p99: (summary.p99_duration || 0) * count,
                total_count: count
              }
            end
          end

          # Convert to final values (weighted averages)
          daily_data = daily_data.transform_values do |data|
            {
              p95: data[:total_count] > 0 ? (data[:total_weighted_p95] / data[:total_count]).round(0) : 0,
              p99: data[:total_count] > 0 ? (data[:total_weighted_p99] / data[:total_count]).round(0) : 0
            }
          end

          # Build labels array
          labels = date_range.map { |date| date.strftime("%b %-d") }

          # Build series data
          series = []

          # Add P95 series (green)
          p95_data = date_range.map { |date| daily_data[date]&.[](:p95) || 0 }
          series << {
            name: "P95",
            data: p95_data,
            type: "line",
            color: "#10b981"  # green
          }

          # Add P99 series (blue)
          p99_data = date_range.map { |date| daily_data[date]&.[](:p99) || 0 }
          series << {
            name: "P99",
            data: p99_data,
            type: "line",
            color: "#3b82f6"  # blue
          }

          # Add Query Service Level Objective series if configured
          slo_config = RailsPulse.configuration.query_service_level_objective
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
