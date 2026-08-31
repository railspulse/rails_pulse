module RailsPulse
  class FindingDetectionJob < ApplicationJob
    # Runs the deterministic regression rules and records what they find.
    #
    # Scheduled once a day rather than hourly: baselines are built from day
    # summaries, which SummaryJob writes at midnight for the day that just
    # ended, so there is nothing new to compare against until the next one
    # lands. SummaryJob invokes this after its daily rollup.
    #
    # @param as_of [Time, nil] treat this as "now" (defaults to the current time)
    # @return [nil]
    def perform(as_of = nil)
      as_of ||= Time.current

      result = FindingDetector.call(as_of: as_of)

      RailsPulse.logger.info(
        "Finding detection complete: #{result.detected} detected, " \
        "#{result.opened} opened, #{result.reopened} reopened, #{result.resolved} resolved"
      )

      nil
    rescue StandardError => e
      RailsPulse.logger.error "Finding detection failed: #{e.message}"
      RailsPulse.logger.error e.backtrace.join("\n")
      raise
    end
  end
end
