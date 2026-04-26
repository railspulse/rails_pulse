module RailsPulse
  class DeploymentsController < ApplicationController
    def create
      deployment = RailsPulse::Deployment.new(
        revision:    deployment_params[:revision],
        deployed_at: deployment_params[:deployed_at].presence || Time.current,
        metadata:    deployment_params[:metadata]&.to_json
      )

      if deployment.save
        render json: { status: "created", id: deployment.id, revision: deployment.revision,
                       deployed_at: deployment.deployed_at }, status: :created
      else
        render json: { status: "error", errors: deployment.errors.full_messages },
               status: :unprocessable_entity
      end
    end

    private

    def deployment_params
      params.require(:deployment).permit(:revision, :deployed_at, metadata: {})
    end
  end
end
