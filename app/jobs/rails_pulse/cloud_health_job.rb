module RailsPulse
  # Sends the health update for the minute just ended to Rails Pulse Cloud,
  # deployments recorded since the last run, and any buffered batches whose
  # retry is due. Schedule it every minute alongside SummaryJob. Does nothing
  # unless config.cloud is set.
  class CloudHealthJob < ApplicationJob
    def perform
      Cloud::Sync.new.minutely
    end
  end
end
