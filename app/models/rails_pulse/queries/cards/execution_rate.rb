module RailsPulse
  module Queries
    module Cards
      class ExecutionRate < RailsPulse::Cards::Base
        def initialize(query: nil, **kwargs)
          super(subject: query, **kwargs)
        end

        def to_metric_card
          # Use base class helper for query construction
          base_query = base_summary_query("RailsPulse::Query")

          metrics = base_query.select(
            window_sql("SUM(CASE WHEN period_start >= :current_start THEN count ELSE 0 END) AS current_count"),
            window_sql("SUM(CASE WHEN period_start >= :range_start AND period_start < :current_start THEN count ELSE 0 END) AS previous_count")
          ).take

          # Calculate metrics from single query result
          current_period_count = metrics.current_count || 0
          previous_period_count = metrics.previous_count || 0

          # Use base class trend calculation
          trend_icon, trend_amount = trend_for(current_period_count, previous_period_count) if show_trend?

          # Create a query for sparkline data using only the current period
          sparkline_query = RailsPulse::Summary
            .with_tag_filters(@disabled_tags, @show_non_tagged)
            .where(
              summarizable_type: "RailsPulse::Query",
              period_type: @period_type,
              period_start: current_window_start..now
            )
          sparkline_query = sparkline_query.where(summarizable_id: @subject.id) if @subject

          grouped_data = bucket_by_period(sparkline_query) { |relation| relation.sum(:count) }

          # Use base class sparkline generation (handles hour vs day automatically)
          sparkline_data = sparkline_from(grouped_data)

          summary = format_rate(current_period_count, current_window_minutes)

          {
            id: "execution_rate",
            context: "queries",
            title: "Execution Rate",
            summary: summary,
            chart_data: sparkline_data,
            trend_icon: trend_icon,
            trend_amount: trend_amount,
            trend_text: (show_trend? ? comparison_period_text : nil),
            period_stat: current_period_count > 0 ? "#{format_number(current_period_count)} executions" : period_date_range,
            help_heading: "Query Execution Rate",
            help_text: "Total database queries executed over the selected range, expressed as an average rate. Spikes may indicate N+1 queries or inefficient data access patterns."
          }
        end
      end
    end
  end
end
