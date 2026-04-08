module RailsPulse
  class CleanupJob < ApplicationJob
    # Performs scheduled cleanup of old RailsPulse data
    # @return [Hash, nil] Stats hash with cleanup results or nil if archiving disabled
    def perform
      return unless RailsPulse.configuration.archiving_enabled

      log_start
      stats = CleanupService.perform
      log_completion(stats)
      stats
    rescue StandardError => e
      log_error(e)
      raise
    end

    private

    def log_start
      RailsPulse.logger.info "[CleanupJob] Starting scheduled cleanup"
    end

    def log_completion(stats)
      RailsPulse.logger.info "[CleanupJob] Cleanup completed - #{stats[:total_deleted]} records deleted"
    end

    def log_error(error)
      RailsPulse.logger.error "[CleanupJob] Cleanup failed: #{error.message}"
      RailsPulse.logger.error error.backtrace.join("\n")
    end
  end
end
