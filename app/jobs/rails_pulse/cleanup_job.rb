module RailsPulse
  class CleanupJob < ApplicationJob
    queue_as :default

    def perform
      return unless RailsPulse.configuration.archiving_enabled

      Rails.logger.info "[RailsPulse::CleanupJob] Starting scheduled cleanup"

      stats = CleanupService.perform

      Rails.logger.info "[RailsPulse::CleanupJob] Cleanup completed - #{stats[:total_deleted]} records deleted"

      stats
    rescue => e
      Rails.logger.error "[RailsPulse::CleanupJob] Cleanup failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end
end
