module RailsPulse
  module Queries
    module Cards
      class ExecutionRate
        def initialize(query: nil, disabled_tags: [], show_non_tagged: true, period: 7, period_type: "day")
          @query = query
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @period = period
          @period_type = period_type
        end

        def to_metric_card
          # For hourly: period is in days (e.g., 1), but we work in hours
          # For daily: period is in days as before
          time_unit = @period_type == "hour" ? 1.hour : 1.day
          last_n_units = @period_type == "hour" ? (@period * 24).hours.ago : @period.days.ago.beginning_of_day
          previous_n_units = @period_type == "hour" ? (@period * 48).hours.ago : (@period * 2).days.ago.beginning_of_day

          # Single query to get all count metrics with conditional aggregation
          base_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Query",
              period_type: @period_type,
              period_start: previous_n_units..Time.current
            )
          base_query = base_query.where(summarizable_id: @query.id) if @query

          last7 = last_n_units.strftime("%Y-%m-%d %H:%M:%S")
          prev7 = previous_n_units.strftime("%Y-%m-%d %H:%M:%S")

          metrics = base_query.select(
            "SUM(count) AS total_count",
            "SUM(CASE WHEN period_start >= '#{last7}' THEN count ELSE 0 END) AS current_count",
            "SUM(CASE WHEN period_start >= '#{prev7}' AND period_start < '#{last7}' THEN count ELSE 0 END) AS previous_count"
          ).take

          # Calculate metrics from single query result
          total_execution_count = metrics.total_count || 0
          current_period_count = metrics.current_count || 0
          previous_period_count = metrics.previous_count || 0

          percentage = previous_period_count.zero? ? 0 : ((previous_period_count - current_period_count) / previous_period_count.to_f * 100).abs.round(1)
          trend_icon = percentage < 0.1 ? "move-right" : current_period_count < previous_period_count ? "trending-down" : "trending-up"
          trend_amount = previous_period_count.zero? ? "0%" : "#{percentage}%"

          # Sparkline data - group by hour or day depending on period_type
          if @period_type == "hour"
            start_time = (@period * 24).hours.ago.beginning_of_hour
            end_time = Time.current.beginning_of_hour

            # Create a separate query for sparkline data using only the current period
            sparkline_query = RailsPulse::Summary
              .with_tag_filters(@disabled_tags, @show_non_tagged)
              .where(
                summarizable_type: "RailsPulse::Query",
                period_type: @period_type,
                period_start: start_time..end_time
              )
            sparkline_query = sparkline_query.where(summarizable_id: @query.id) if @query

            grouped_data = sparkline_query.group_by_hour(:period_start).sum(:count)

            sparkline_data = {}
            current_time = start_time
            while current_time <= end_time
              total = grouped_data[current_time] || 0
              # Use timestamp in milliseconds as key to preserve uniqueness across days
              sparkline_data[current_time.to_i * 1000] = { value: total }
              current_time += 1.hour
            end
          else
            grouped_data = base_query.group_by_date(:period_start).sum(:count)

            start_day = @period.days.ago.beginning_of_day.to_date
            end_day = Time.current.to_date

            sparkline_data = {}
            (start_day..end_day).each do |day|
              total = grouped_data[day] || 0
              label = day.strftime("%b %-d")
              sparkline_data[label] = { value: total }
            end
          end

          # Calculate appropriate rate display based on frequency
          total_minutes = (@period_type == "hour" ? (@period * 24).hours : (@period * 2).days) / 1.minute.to_f
          executions_per_minute = total_execution_count.to_f / total_minutes

          # Choose appropriate time unit for display
          if executions_per_minute >= 1
            summary = "#{executions_per_minute.round(2)} / min"
          elsif executions_per_minute * 60 >= 1
            executions_per_hour = executions_per_minute * 60
            summary = "#{executions_per_hour.round(2)} / hour"
          else
            executions_per_day = executions_per_minute * 60 * 24
            summary = "#{executions_per_day.round(2)} / day"
          end

          {
            id: "execution_rate",
            context: "queries",
            title: "Execution Rate",
            summary: summary,
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week",
            help_heading: "Query Execution Rate",
            help_text: "Total database queries executed over the last 14 days, expressed as an average rate. Spikes may indicate N+1 queries or inefficient data access patterns."
          }
        end
      end
    end
  end
end
