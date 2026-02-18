module RailsPulse
  class SummaryJob < ApplicationJob
    def perform(target_hour = nil)
      target_hour ||= 1.hour.ago.beginning_of_hour

      # Always run hourly summary
      process_hourly_summary(target_hour)

      # Check if we should run daily summary (at the start of a new day)
      if target_hour.hour == 0
        process_daily_summary(target_hour.to_date - 1.day)

        # Check if we should run weekly summary (Monday at midnight)
        if target_hour.wday == 1
          process_weekly_summary((target_hour.to_date - 1.week).beginning_of_week)
        end

        # Check if we should run monthly summary (first day of month)
        if target_hour.day == 1
          process_monthly_summary((target_hour.to_date - 1.month).beginning_of_month)
        end
      end
    rescue => e
      RailsPulse.logger.error "Summary job failed: #{e.message}"
      RailsPulse.logger.error e.backtrace.join("\n")
      raise
    end

    private

    def process_hourly_summary(hour)
      RailsPulse.logger.info "Processing hourly summary for #{hour}"
      SummaryService.new("hour", hour).perform
    end

    def process_daily_summary(date)
      RailsPulse.logger.info "Processing daily summary for #{date}"
      SummaryService.new("day", date).perform
    end

    def process_weekly_summary(week_start)
      RailsPulse.logger.info "Processing weekly summary for week starting #{week_start}"
      SummaryService.new("week", week_start).perform
    end

    def process_monthly_summary(month_start)
      RailsPulse.logger.info "Processing monthly summary for month starting #{month_start}"
      SummaryService.new("month", month_start).perform
    end
  end
end
