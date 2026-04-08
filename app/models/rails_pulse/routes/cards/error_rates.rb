module RailsPulse
  module Routes
    module Cards
      class ErrorRates < RailsPulse::Cards::Base
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
            "SUM(error_count) AS total_errors",
            "SUM(status_4xx) AS total_4xx",
            "SUM(count) AS total_requests",
            "SUM(CASE WHEN period_start >= #{quote(current_window_start)} THEN error_count + status_4xx ELSE 0 END) AS current_total_errors",
            "SUM(CASE WHEN period_start >= #{quote(range_start)} AND period_start < #{quote(current_window_start)} THEN error_count + status_4xx ELSE 0 END) AS previous_total_errors"
          ).take

          total_errors = metrics.total_errors || 0
          total_4xx = metrics.total_4xx || 0
          total_requests = metrics.total_requests || 0
          current_total = metrics.current_total_errors || 0
          previous_total = metrics.previous_total_errors || 0

          has_data = total_requests > 0

          server_rate = has_data ? (total_errors.to_f / total_requests * 100).round(2) : 0
          client_rate = has_data ? (total_4xx.to_f / total_requests * 100).round(2) : 0

          # Use base class trend calculation
          trend_icon, trend_amount = if has_data
            trend_for(current_total, previous_total)
          else
            [ "move-right", "—" ]
          end

          # Build sparkline data using base class helpers
          sparkline_query = build_sparkline_query("RailsPulse::Route")
          grouped_errors = group_sparkline_by_period(sparkline_query, :error_count)
          grouped_4xx = group_sparkline_by_period(sparkline_query, :status_4xx)

          # Combine error counts for each period
          combined_errors = grouped_errors.merge(grouped_4xx) { |_key, errors, fourxx| errors + fourxx }

          # Use base class sparkline generation (handles hour vs day automatically)
          sparkline_data = sparkline_from(combined_errors)

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

        private

        def subject_id
          @route&.id
        end
      end
    end
  end
end
