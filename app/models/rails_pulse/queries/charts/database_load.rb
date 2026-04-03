module RailsPulse
  module Queries
    module Charts
      class DatabaseLoad
        def initialize(disabled_tags: [], show_non_tagged: true)
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
        end

        def to_chart_data
          start_date = 2.weeks.ago.beginning_of_day.to_date
          end_date = Time.current.to_date
          date_range = (start_date..end_date)

          # Get query summaries (DB time)
          query_summaries = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Query",
              period_type: "day",
              period_start: start_date.beginning_of_day..end_date.end_of_day
            )

          # Get route summaries (total request time)
          route_summaries = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: "day",
              period_start: start_date.beginning_of_day..end_date.end_of_day
            )

          return nil if query_summaries.empty? || route_summaries.empty?

          # Group by day
          daily_query_time = {}
          query_summaries.each do |summary|
            date = summary.period_start.to_date
            daily_query_time[date] ||= 0
            daily_query_time[date] += summary.total_duration || 0
          end

          daily_request_time = {}
          route_summaries.each do |summary|
            date = summary.period_start.to_date
            daily_request_time[date] ||= 0
            daily_request_time[date] += summary.total_duration || 0
          end

          # Calculate daily percentages
          daily_percentages = date_range.map do |date|
            query_time = daily_query_time[date] || 0
            request_time = daily_request_time[date] || 0
            request_time > 0 ? (query_time.to_f / request_time * 100).round(1) : 0
          end

          # Build labels
          labels = date_range.map { |date| date.strftime("%b %-d") }

          # Color bars based on threshold
          # <25% = green (healthy)
          # 25-40% = yellow (watch)
          # >40% = red (bottleneck)
          bar_colors = daily_percentages.map do |percentage|
            if percentage < 25
              "rgb(34, 197, 94)"  # green
            elsif percentage < 40
              "rgb(234, 179, 8)"  # yellow
            else
              "rgb(239, 68, 68)"  # red
            end
          end

          {
            labels: labels,
            series: [
              {
                name: "DB Load",
                data: daily_percentages,
                type: "bar",
                color: bar_colors
              }
            ]
          }
        end
      end
    end
  end
end
