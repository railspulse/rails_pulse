module RailsPulse
  module Routes
    module Cards
      class ErrorRates
        def initialize(route: nil, disabled_tags: [], show_non_tagged: true, period: 7, period_type: "day")
          @route = route
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @period = period
          @period_type = period_type
        end

        def to_metric_card
          last_n_units = @period_type == "hour" ? (@period * 24).hours.ago : @period.days.ago.beginning_of_day
          previous_n_units = @period_type == "hour" ? (@period * 48).hours.ago : (@period * 2).days.ago.beginning_of_day
          last7 = last_n_units.strftime("%Y-%m-%d %H:%M:%S")
          prev7 = previous_n_units.strftime("%Y-%m-%d %H:%M:%S")

          base_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: @period_type,
              period_start: previous_n_units..Time.current
            )
          base_query = base_query.where(summarizable_id: @route.id) if @route

          metrics = base_query.select(
            "SUM(error_count) AS total_errors",
            "SUM(status_4xx) AS total_4xx",
            "SUM(count) AS total_requests",
            "SUM(CASE WHEN period_start >= '#{last7}' THEN error_count + status_4xx ELSE 0 END) AS current_total_errors",
            "SUM(CASE WHEN period_start >= '#{prev7}' AND period_start < '#{last7}' THEN error_count + status_4xx ELSE 0 END) AS previous_total_errors"
          ).take

          total_errors = metrics.total_errors || 0
          total_4xx = metrics.total_4xx || 0
          total_requests = metrics.total_requests || 0
          current_total = metrics.current_total_errors || 0
          previous_total = metrics.previous_total_errors || 0

          has_data = total_requests > 0

          server_rate = has_data ? (total_errors.to_f / total_requests * 100).round(2) : 0
          client_rate = has_data ? (total_4xx.to_f / total_requests * 100).round(2) : 0

          if has_data
            percentage = previous_total.zero? ? 0 : ((previous_total - current_total) / previous_total.to_f * 100).abs.round(1)
            trend_icon = percentage < 0.1 ? "move-right" : current_total < previous_total ? "trending-down" : "trending-up"
            trend_amount = previous_total.zero? ? "0%" : "#{percentage}%"
          else
            trend_icon = "move-right"
            trend_amount = "—"
          end

          # Sparkline shows combined error count - group by hour or day
          sparkline_data = {}
          if @period_type == "hour"
            start_time = (@period * 24).hours.ago.beginning_of_hour
            end_time = Time.current.beginning_of_hour

            # Create a separate query for sparkline data using only the current period
            sparkline_query = RailsPulse::Summary
              .with_tag_filters(@disabled_tags, @show_non_tagged)
              .where(
                summarizable_type: "RailsPulse::Route",
                period_type: @period_type,
                period_start: start_time..end_time
              )
            sparkline_query = sparkline_query.where(summarizable_id: @route.id) if @route

            grouped_errors = sparkline_query.group_by_hour(:period_start).sum(:error_count)
            grouped_4xx = sparkline_query.group_by_hour(:period_start).sum(:status_4xx)

            current_time = start_time
            index = 0
            while current_time <= end_time
              total = (grouped_errors[current_time] || 0) + (grouped_4xx[current_time] || 0)
              # Use index as key to preserve order and avoid timezone issues
              sparkline_data[index.to_s] = { value: total }
              current_time += 1.hour
              index += 1
            end
          else
            grouped_errors = base_query.group_by_date(:period_start).sum(:error_count)
            grouped_4xx = base_query.group_by_date(:period_start).sum(:status_4xx)

            start_day = @period.days.ago.beginning_of_day.to_date
            end_day = Time.current.to_date

            (start_day..end_day).each do |day|
              total = (grouped_errors[day] || 0) + (grouped_4xx[day] || 0)
              sparkline_data[day.strftime("%b %-d")] = { value: total }
            end
          end

          total_rate = has_data ? (server_rate + client_rate).round(2) : 0
          summary = has_data ? "#{total_rate}% of requests" : "—"

          {
            id: "error_rates",
            chart_color: RailsPulse::ChartColors::DEFAULT,
            context: "routes",
            title: "Error Rate",
            summary: summary,
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week",
            help_heading: "Error Rates",
            help_text: "Combined 5xx and 4xx error rate over the last 2 weeks. 5xx server errors indicate bugs or infrastructure issues. 4xx client errors may indicate broken API consumers or deprecated endpoints."
          }
        end
      end
    end
  end
end
