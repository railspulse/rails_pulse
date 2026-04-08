module RailsPulse
  module Routes
    module Cards
      class PercentileResponseTimes < RailsPulse::Cards::Base
        def initialize(route: nil, disabled_tags: [], show_non_tagged: true, period: 7, period_type: "day")
          @route = route
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @period = period
          @period_type = period_type
        end

        def to_metric_card
          # Use base class helper for query construction
          base_query = base_summary_query("RailsPulse::Route")

          metrics = base_query.select(
            "SUM(p95_duration * count) / NULLIF(SUM(count), 0) AS overall_p95",
            "SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN p95_duration * count ELSE 0 END) / NULLIF(SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN count ELSE 0 END), 0) AS current_p95",
            "SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN p95_duration * count ELSE 0 END) / NULLIF(SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN count ELSE 0 END), 0) AS previous_p95",
            "SUM(count) AS total_count"
          ).take

          # Calculate metrics from single query result
          p95_response_time = (metrics&.overall_p95 || 0).round(0)
          current_period_p95 = metrics&.current_p95 || 0
          previous_period_p95 = metrics&.previous_p95 || 0

          has_data = metrics.total_count.to_i > 0

          # Use base class trend calculation
          trend_icon, trend_amount = if has_data
            trend_for(current_period_p95, previous_period_p95)
          else
            [ "move-right", "—" ]
          end

          # Create sparkline query using only the current period
          sparkline_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: @period_type,
              period_start: current_window_start..now
            )
          sparkline_query = sparkline_query.where(summarizable_id: @route.id) if @route

          if period_type_hours?
            weighted_sums = sparkline_query.group_by_hour(:period_start).sum("p95_duration * count")
            period_counts = sparkline_query.group_by_hour(:period_start).sum(:count)
          else
            weighted_sums = sparkline_query.group_by_date(:period_start).sum("p95_duration * count")
            period_counts = sparkline_query.group_by_date(:period_start).sum(:count)
          end

          # Calculate weighted averages for each period
          averages_by_period = weighted_sums.each_with_object({}) do |(period, weighted), hash|
            count = period_counts[period].to_i
            hash[period] = count > 0 ? (weighted.to_f / count).round(0) : 0
          end

          # Use base class sparkline generation (handles hour vs day automatically)
          sparkline_data = sparkline_from(averages_by_period)

          {
            id: "percentile_response_times",
            chart_color: RailsPulse::ChartColors::P95,
            context: "routes",
            title: "P95 Response Time",
            summary: has_data ? "#{p95_response_time} ms" : "—",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week",
            help_heading: "P95 Response Time",
            help_text: "The 95th percentile response time — 95% of requests are faster than this. Weighted by request volume across all routes. A rising P95 indicates increasing slowness affecting your users."
          }
        end

        private

        def subject_id
          @route&.id
        end
      end
    end
  end
end
