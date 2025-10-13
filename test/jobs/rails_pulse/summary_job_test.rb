require "test_helper"

module RailsPulse
  class SummaryJobTest < ActiveJob::TestCase
    # TODO: Test that perform calls process_hourly_summary with target hour
    # TODO: Test that perform uses 1.hour.ago.beginning_of_hour as default target_hour
    # TODO: Test that process_daily_summary is called when target_hour.hour == 0
    # TODO: Test that process_weekly_summary is called on Monday at midnight
    # TODO: Test that process_monthly_summary is called on first day of month
    # TODO: Test that SummaryService is called with correct period type and time for each summary type
    # TODO: Test error handling and logging when job fails
    # TODO: Test that errors are raised after logging
  end
end
