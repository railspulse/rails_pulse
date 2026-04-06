module RailsPulse
  module Dashboard
    module Charts
      class ThroughputAndErrors
        def initialize(disabled_tags: [], show_non_tagged: true, period: 7, period_type: "day")
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @period = period
          @period_type = period_type
        end

        def to_chart_data
          if @period_type == "hour"
            start_time = (@period * 24).hours.ago.beginning_of_hour
            end_time = Time.current.beginning_of_hour

            summaries = RailsPulse::Summary
              .with_tag_filters(@disabled_tags, @show_non_tagged)
              .where(
                summarizable_type: "RailsPulse::Route",
                period_type: "hour",
                period_start: start_time..end_time
              )
              .group(:period_start)
              .select(
                :period_start,
                "SUM(count) as total_count",
                "SUM(error_count) as total_errors"
              )

            return nil if summaries.empty?

            hourly_data = {}
            summaries.each do |summary|
              time_key = summary.period_start.beginning_of_hour
              hourly_data[time_key] = {
                requests: summary.total_count || 0,
                errors: summary.total_errors || 0
              }
            end

            # Build hourly time range
            time_range = []
            current_time = start_time
            while current_time <= end_time
              time_range << current_time
              current_time += 1.hour
            end

            labels = time_range.map { |time| time.strftime("%H:%M") }

            series = [
              {
                name: "Requests",
                data: time_range.map { |time| hourly_data[time]&.[](:requests) || 0 },
                type: "bar",
                color: RailsPulse::ChartColors::DEFAULT,
                itemStyle: { borderRadius: [ 5, 5, 0, 0 ] },
                z: 1
              },
              {
                name: "Errors",
                data: time_range.map { |time| hourly_data[time]&.[](:errors) || 0 },
                type: "bar",
                color: "#dc2626",
                itemStyle: { borderRadius: [ 5, 5, 0, 0 ] },
                barGap: "-100%",
                z: 2
              }
            ]
          else
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
          end

          { labels: labels, series: series }
        end
      end
    end
  end
end
