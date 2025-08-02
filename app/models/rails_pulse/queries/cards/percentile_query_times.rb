module RailsPulse
  module Queries
    module Cards
      class PercentileQueryTimes
        def initialize(query: nil)
          @query = query
        end

        def to_metric_card
          operations = if @query
            RailsPulse::Operation.where(query: @query)
          else
            RailsPulse::Operation.all
          end

          # Calculate overall 95th percentile response time
          count = operations.count
          percentile_95th = if count > 0
            operations.select("duration").order("duration").limit(1).offset((count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

          # Calculate trend by comparing last 7 days vs previous 7 days for 95th percentile
          last_7_days = 7.days.ago.beginning_of_day
          previous_7_days = 14.days.ago.beginning_of_day

          current_period = operations.where("occurred_at >= ?", last_7_days)
          current_count = current_period.count
          current_period_95th = if current_count > 0
            current_period.select("duration").order("duration").limit(1).offset((current_count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

          previous_period = operations.where("occurred_at >= ? AND occurred_at < ?", previous_7_days, last_7_days)
          previous_count = previous_period.count
          previous_period_95th = if previous_count > 0
            previous_period.select("duration").order("duration").limit(1).offset((previous_count * 0.95).floor).pluck(:duration).first || 0
          else
            0
          end

          percentage = previous_period_95th.zero? ?  0 : ((previous_period_95th - current_period_95th) / previous_period_95th * 100).abs.round(1)
          trend_icon = percentage < 0.1 ?  "move-right" : current_period_95th < previous_period_95th ? "trending-down" : "trending-up"
          trend_amount = previous_period_95th.zero? ? "0%" : "#{percentage}%"

          sparkline_data = operations
            .group_by_week(:occurred_at, time_zone: "UTC")
            .average(:duration)
            .each_with_object({}) do |(date, avg), hash|
              formatted_date = date.strftime("%b %-d")
              value = avg&.round(0) || 0
              hash[formatted_date] = {
                value: value
              }
            end

          {
            title: "95th Percentile Query Time",
            summary: "#{percentile_95th} ms",
            line_chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week"
          }
        end
      end
    end
  end
end
