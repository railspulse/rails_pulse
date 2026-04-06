module RailsPulse
  module Dashboard
    module Charts
      class ThroughputAndErrors
        def initialize(disabled_tags: [], show_non_tagged: true, period: 7)
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @period = period
        end

        def to_chart_data
          start_date = @period.days.ago.beginning_of_day.to_date
          end_date = Time.current.to_date
          date_range = (start_date..end_date)

          summaries = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: "day",
              period_start: start_date.beginning_of_day..end_date.end_of_day
            )
            .group(:period_start)
            .select(
              :period_start,
              "SUM(count) as total_count",
              "SUM(error_count) as total_errors"
            )

          return nil if summaries.empty?

          daily_data = {}
          summaries.each do |summary|
            date = summary.period_start.to_date
            daily_data[date] = {
              requests: summary.total_count || 0,
              errors: summary.total_errors || 0
            }
          end

          labels = date_range.map { |date| date.strftime("%b %-d") }

          series = [
            {
              name: "Requests",
              data: date_range.map { |date| daily_data[date]&.[](:requests) || 0 },
              type: "bar",
              color: RailsPulse::ChartColors::DEFAULT,
              itemStyle: { borderRadius: [ 5, 5, 0, 0 ] },
              z: 1
            },
            {
              name: "Errors",
              data: date_range.map { |date| daily_data[date]&.[](:errors) || 0 },
              type: "bar",
              color: "#dc2626",
              itemStyle: { borderRadius: [ 5, 5, 0, 0 ] },
              barGap: "-100%",
              z: 2
            }
          ]

          { labels: labels, series: series }
        end
      end
    end
  end
end
