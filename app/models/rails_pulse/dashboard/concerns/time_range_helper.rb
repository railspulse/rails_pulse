module RailsPulse
  module Dashboard
    module Concerns
      module TimeRangeHelper
        private

        def period_range
          return [ @window.start_time, @window.end_time ] if @window

          [ @period.days.ago.beginning_of_day, Time.current ]
        end

        # Summary rows that cover the period exactly once. The same traffic is
        # summarized per hour, day, week and month, so summing across period
        # types would count it once per granularity. A window of 25 hours or
        # less reads hourly rows. A longer one reads daily rows up to the start
        # of today and hourly rows after it, because a day is summarized only
        # once it has ended.
        def period_summaries
          start, finish = period_range
          return RailsPulse::Summary.where(period_type: "hour", period_start: start..finish) if hourly_period?(start, finish)

          today = Time.zone.now.beginning_of_day
          RailsPulse::Summary.where(period_type: "day", period_start: start...today)
            .or(RailsPulse::Summary.where(period_type: "hour", period_start: today..finish))
        end

        # The dashboard passes the period type TimeRange resolved, so these
        # panels read the same granularity as the cards and charts beside them.
        def hourly_period?(start, finish)
          return @period_type == "hour" if @period_type

          finish - start <= 25.hours
        end
      end
    end
  end
end
