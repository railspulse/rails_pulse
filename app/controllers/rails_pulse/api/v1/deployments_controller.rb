module RailsPulse
  module Api
    module V1
      class DeploymentsController < BaseController
        def index
          parsed_range = time_range
          return unless parsed_range
          since_start, until_end = parsed_range

          collection = RailsPulse::Deployment.recent.order(id: :desc)
          collection = collection.where(started_at: since_start..) if since_start
          collection = collection.where(started_at: ..until_end) if until_end
          collection = apply_revision_filter(collection)

          data, meta = paginated(collection)
          deployments = data.to_a
          comparisons = RailsPulse::DeploymentComparison.for(deployments)

          render json: {
            data: deployments.map { |deployment| DeploymentSerializer.serialize(deployment, comparison: comparisons[deployment.id]) },
            meta: meta
          }
        end

        private

        # The full revision or the start of one, so the short SHA a person
        # reads from the CLI finds the same deployment as the full SHA.
        def apply_revision_filter(scope)
          return scope unless params[:revision].present?

          scope.where(
            "revision LIKE :prefix #{RailsPulse::LikePattern::CLAUSE}",
            prefix: RailsPulse::LikePattern.starting_with(params[:revision])
          )
        end
      end
    end
  end
end
