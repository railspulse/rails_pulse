require "test_helper"

module RailsPulse
  class CleanupJobTest < ActiveJob::TestCase
    # TODO: Test that perform returns early when archiving is disabled
    # TODO: Test that CleanupService.perform is called when archiving is enabled
    # TODO: Test that job returns stats hash with total_deleted count
    # TODO: Test that job logs start and completion messages
    # TODO: Test error handling and logging when cleanup fails
    # TODO: Test that errors are raised after logging
  end
end
