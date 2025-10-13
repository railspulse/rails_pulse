module RailsPulse
  module Requests
    module Tables
      class Index
        def initialize(ransack_query:, period_type: nil, start_time:, params:)
          @ransack_query = ransack_query
          @period_type = period_type
          @start_time = start_time
          @params = params
        end

        def to_table
          # Check if we have explicit ransack sorts
          has_sorts = @ransack_query.sorts.any?

          base_query = @ransack_query.result(distinct: false)
            .where(
              summarizable_type: "RailsPulse::Request",
              summarizable_id: 0,  # Overall request summaries
              period_type: @period_type
            )

          # Apply grouping and aggregation for time periods
          grouped_query = base_query
            .group(
              "rails_pulse_summaries.period_start",
              "rails_pulse_summaries.period_end",
              "rails_pulse_summaries.period_type"
            )
            .select(
              "rails_pulse_summaries.period_start",
              "rails_pulse_summaries.period_end",
              "rails_pulse_summaries.period_type",
              "AVG(rails_pulse_summaries.avg_duration) as avg_duration",
              "MAX(rails_pulse_summaries.max_duration) as max_duration",
              "MIN(rails_pulse_summaries.min_duration) as min_duration",
              "SUM(rails_pulse_summaries.count) as count",
              "SUM(rails_pulse_summaries.error_count) as error_count",
              "SUM(rails_pulse_summaries.success_count) as success_count"
            )

          # Apply sorting based on ransack sorts or use default
          if has_sorts
            # Apply custom sorting based on ransack parameters
            sort = @ransack_query.sorts.first
            direction = sort.dir == "desc" ? :desc : :asc

            case sort.name
            when "avg_duration"
              grouped_query = grouped_query.order(Arel.sql("AVG(rails_pulse_summaries.avg_duration)").send(direction))
            when "max_duration"
              grouped_query = grouped_query.order(Arel.sql("MAX(rails_pulse_summaries.max_duration)").send(direction))
            when "min_duration"
              grouped_query = grouped_query.order(Arel.sql("MIN(rails_pulse_summaries.min_duration)").send(direction))
            when "count"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count)").send(direction))
            when "requests_per_minute"
              grouped_query = grouped_query.order(Arel.sql("SUM(rails_pulse_summaries.count) / 60.0").send(direction))
            when "error_rate_percentage"
              grouped_query = grouped_query.order(Arel.sql("(SUM(rails_pulse_summaries.error_count) * 100.0) / SUM(rails_pulse_summaries.count)").send(direction))
            when "period_start"
              grouped_query = grouped_query.order(period_start: direction)
            else
              # Unknown sort field, fallback to default
              grouped_query = grouped_query.order(period_start: :desc)
            end
          else
            # Apply default sort when no explicit sort is provided (matches controller default_table_sort)
            grouped_query = grouped_query.order(period_start: :desc)
          end

          grouped_query
        end
      end
    end
  end
end
