require "rails_pulse/version"
require "rails_pulse/engine"
require "rails_pulse/configuration"
require "rails_pulse/cleanup_service"

module RailsPulse
  class << self
    attr_accessor :configuration

    def configure
      self.configuration ||= Configuration.new
      yield(configuration)
      configuration.validate_configuration!
    end

    def clear_metric_cache!
      Rails.cache.delete_matched("rails_pulse_metric*")
    end

    def warm_metric_cache!
      # Pre-warm cache for common metrics
      [ :average_response_times, :percentile_response_times, :request_count_totals, :error_rate_per_route ].each do |metric|
        begin
          Rails.logger.info "Warming cache for metric: #{metric}"
          # This would trigger cache generation by making the request
        rescue => e
          Rails.logger.error "Failed to warm cache for #{metric}: #{e.message}"
        end
      end
    end

    def connects_to
      configuration&.connects_to
    end
  end

  # Ensure configuration is initialized
  self.configuration ||= Configuration.new
end
