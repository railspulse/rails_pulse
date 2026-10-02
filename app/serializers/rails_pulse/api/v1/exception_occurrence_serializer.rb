module RailsPulse
  module Api
    module V1
      class ExceptionOccurrenceSerializer
        def self.serialize(occurrence)
          {
            id:             occurrence.id,
            exception_class: occurrence.exception_class,
            message:        occurrence.message,
            occurred_at:    occurrence.occurred_at,
            request_method: occurrence.request_method,
            request_url:    occurrence.request_url,
            request_params: occurrence.request_params.presence,
            environment:    occurrence.environment,
            deploy_sha:     occurrence.deploy_sha,
            backtrace:      Array(occurrence.backtrace)
          }
        end
      end
    end
  end
end
