module RailsPulse
  class BackfillSummariesJob < ApplicationJob
    # Backfills summary data for a date range
    # @param start_date [String, Date, Time] Start of the backfill range
    # @param end_date [String, Date, Time] End of the backfill range
    # @param period_types [Array<String>] Period types to backfill (default: ["hour", "day"])
    # @return [nil]
    def perform(start_date, end_date, period_types = [ "hour", "day" ])
      # A Date or date string means midnight in the aggregation time zone, so
      # backfilled periods land on the boundaries the scheduled job writes.
      start_date = start_date.in_time_zone
      end_date = end_date.in_time_zone

      period_types.each do |period_type|
        backfill_period(period_type, start_date, end_date)
      end
    end

    private

    def backfill_period(period_type, start_date, end_date)
      current = Summary.normalize_period_start(period_type, start_date)
      period_end = Summary.calculate_period_end(period_type, end_date)

      while current <= period_end
        RailsPulse.logger.info "Backfilling #{period_type} summary for #{current}"

        SummaryService.new(period_type, current).perform

        current = advance_period(current, period_type)

        # Add small delay to avoid overwhelming the database
        sleep 0.1
      end
    end

    def advance_period(time, period_type)
      case period_type
      when "hour"  then time + 1.hour
      when "day"   then time + 1.day
      when "week"  then time + 1.week
      when "month" then time + 1.month
      end
    end
  end
end
