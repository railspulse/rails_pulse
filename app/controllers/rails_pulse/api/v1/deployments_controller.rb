module RailsPulse
  module Api
    module V1
      class DeploymentsController < BaseController
        def index
          parsed_range = time_range
          return unless parsed_range
          since_start, until_end = parsed_range

          collection = RailsPulse::Deployment.recent
          collection = collection.where(started_at: since_start..) if since_start
          collection = collection.where(started_at: ..until_end) if until_end

          data, meta = paginated(collection)

          render json: {
            data: data.map { |deployment| DeploymentSerializer.serialize(deployment) },
            meta: meta
          }
        end
      end
    end
  end
end
