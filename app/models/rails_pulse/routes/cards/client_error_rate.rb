module RailsPulse
  module Routes
    module Cards
      class ClientErrorRate < RailsPulse::Cards::Base
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
            "SUM(status_4xx) AS total_4xx",
            "SUM(count) AS total_requests",
            "SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN status_4xx ELSE 0 END) AS current_4xx",
            "SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN status_4xx ELSE 0 END) AS previous_4xx"
          ).take

          total_4xx = metrics.total_4xx || 0
          total_requests = metrics.total_requests || 0
          current_period_4xx = metrics.current_4xx || 0
          previous_period_4xx = metrics.previous_4xx || 0

          has_data = total_requests > 0

          overall_rate = has_data ? (total_4xx.to_f / total_requests * 100).round(2) : 0

          # Use base class trend calculation
          trend_icon, trend_amount = if has_data
            trend_for(current_period_4xx, previous_period_4xx)
          else
            [ "move-right", "—" ]
          end

          # Get sparkline data
          grouped_daily = base_query
            .group_by_date(:period_start)
            .sum(:status_4xx)

          # Use base class sparkline generation
          sparkline_data = sparkline_from(grouped_daily)

          {
            id: "client_error_rate",
            chart_color: RailsPulse::ChartColors::DEFAULT,
            context: "routes",
            title: "Client Error Rate",
            summary: has_data ? "#{overall_rate}%" : "—",
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: "Compared to last week",
            help_heading: "Client Error Rate (4xx)",
            help_text: "Percentage of requests returning 4xx status codes (Not Found, Unauthorized, etc). High rates may indicate broken API consumers, deprecated endpoints still in use, or misconfigured clients."
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
