module RailsPulse
  class CleanupJob < ApplicationJob
    def perform
      return unless RailsPulse.configuration.archiving_enabled

      RailsPulse.logger.info "[CleanupJob] Starting scheduled cleanup"

      stats = CleanupService.perform

      RailsPulse.logger.info "[CleanupJob] Cleanup completed - #{stats[:total_deleted]} records deleted"

      stats
    rescue => e
      RailsPulse.logger.error "[CleanupJob] Cleanup failed: #{e.message}"
      RailsPulse.logger.error e.backtrace.join("\n")
      raise
    end
  end
end
