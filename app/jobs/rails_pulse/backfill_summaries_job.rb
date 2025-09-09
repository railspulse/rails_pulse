module RailsPulse
  class BackfillSummariesJob < ApplicationJob
    queue_as :low_priority

    def perform(start_date, end_date, period_types = [ "hour", "day" ])
      start_date = start_date.to_datetime
      end_date = end_date.to_datetime

      period_types.each do |period_type|
        backfill_period(period_type, start_date, end_date)
      end
    end

    private

    def backfill_period(period_type, start_date, end_date)
      current = Summary.normalize_period_start(period_type, start_date)
      period_end = Summary.calculate_period_end(period_type, end_date)

      while current <= period_end
        Rails.logger.info "[RailsPulse] Backfilling #{period_type} summary for #{current}"

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
