module RailsPulse
  # Sends newly summarized hours, changed exception groups and deployments to
  # Rails Pulse Cloud. SummaryJob enqueues it once its summaries are written,
  # so it needs no schedule of its own. Does nothing unless config.cloud is
  # set.
  class CloudSyncJob < ApplicationJob
    def perform
      Cloud::Sync.new.hourly
    end
  end
end
