module RailsPulse
  class SummaryJob < ApplicationJob
    # Performs periodic summary aggregation (hourly/daily/weekly/monthly)
    # @param target_hour [Time, nil] The hour to summarize (defaults to 1 hour ago)
    # @return [nil]
    def perform(target_hour = nil)
      target_hour ||= 1.hour.ago.beginning_of_hour

      # Always run hourly summary
      process_hourly_summary(target_hour)

      # Check if we should run daily summary (at the start of a new day)
      if midnight?(target_hour)
        process_daily_summary(target_hour.to_date - 1.day)

        # Regression detection compares complete days, so it has nothing new to
        # say until the day summary it reads has been written.
        detect_findings(target_hour)

        # Check if we should run weekly summary (Monday at midnight)
        process_weekly_summary((target_hour.to_date - 1.week).beginning_of_week) if monday?(target_hour)

        # Check if we should run monthly summary (first day of month)
        process_monthly_summary((target_hour.to_date - 1.month).beginning_of_month) if first_of_month?(target_hour)
      end
    rescue StandardError => e
      log_error(e)
      raise
    end

    private

    def midnight?(time)
      time.hour == 0
    end

    def monday?(time)
      time.wday == 1
    end

    def first_of_month?(time)
      time.day == 1
    end

    # Detection failing must not take the summary job down with it: summaries
    # are the data everything else depends on, findings are derived from them.
    def detect_findings(as_of)
      RailsPulse.logger.info "Detecting findings as of #{as_of}"
      FindingDetectionJob.perform_now(as_of)
    rescue StandardError => e
      RailsPulse.logger.error "Finding detection failed, summaries unaffected: #{e.message}"
    end

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

    def log_error(error)
      RailsPulse.logger.error "Summary job failed: #{error.message}"
      RailsPulse.logger.error error.backtrace.join("\n")
    end
  end
end
