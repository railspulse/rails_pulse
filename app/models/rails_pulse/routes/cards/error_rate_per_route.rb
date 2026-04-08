module RailsPulse
  module Routes
    module Cards
      class ErrorRatePerRoute < RailsPulse::Cards::Base
        def initialize(route: nil, disabled_tags: [], show_non_tagged: true, period: 7)
          @route = route
          @disabled_tags = disabled_tags
          @show_non_tagged = show_non_tagged
          @period = period
          @period_type = "day"  # This card only supports day period
        end

        def to_metric_card
          # Use base class helper for query construction
          base_query = base_summary_query("RailsPulse::Route")

          metrics = base_query.select(
            "SUM(error_count) AS total_errors",
            "SUM(count) AS total_requests",
            "SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN error_count ELSE 0 END) AS current_errors",
            "SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN error_count ELSE 0 END) AS previous_errors"
          ).take

          # Calculate metrics from single query result
          total_errors = metrics.total_errors || 0
          total_requests = metrics.total_requests || 0
          current_period_errors = metrics.current_errors || 0
          previous_period_errors = metrics.previous_errors || 0

          has_data = total_requests > 0

          # Calculate overall error rate percentage
          overall_error_rate = has_data ? (total_errors.to_f / total_requests * 100).round(2) : 0

          # Use base class trend calculation
          trend_icon, trend_amount = if has_data
            trend_for(current_period_errors, previous_period_errors)
          else
            [ "move-right", "—" ]
          end

          # Get sparkline data
          grouped_daily = base_query
            .group_by_date(:period_start)
            .sum(:error_count)

          # Use base class sparkline generation
          sparkline_data = sparkline_from(grouped_daily)

          {
            id: "error_rate_per_route",
            chart_color: RailsPulse::ChartColors::DEFAULT,
            context: "routes",
            title: "Error Rate Per Route",
            summary: has_data ? "#{overall_error_rate}%" : "—",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week",
            help_heading: "Server Error Rate (5xx)",
            help_text: "Percentage of requests returning 5xx status codes. Server errors indicate bugs, crashes, or infrastructure issues requiring immediate attention."
          }
        end

        private

        def subject_id
          @route&.id
        end

        # Override to show full 14-day sparkline instead of just 7 days
        def sparkline_start
          range_start
        end
      end
    end
  end
end
