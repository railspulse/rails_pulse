module RailsPulse
  class DeploymentsController < ApplicationController
    def create
      deployment = RailsPulse::Deployment.new(
        revision:    deployment_params[:revision],
        started_at:  deployment_params[:started_at].presence || Time.current,
        finished_at: deployment_params[:finished_at].presence,
        metadata:    deployment_params[:metadata]&.to_json
      )

      if deployment.save
        render json: { status: "created", id: deployment.id, revision: deployment.revision,
                       started_at: deployment.started_at, finished_at: deployment.finished_at }, status: :created
      else
        render json: { status: "error", errors: deployment.errors.full_messages },
               status: :unprocessable_content
      end
    end

    private

    def deployment_params
      params.require(:deployment).permit(:revision, :started_at, :finished_at, metadata: {})
    end
  end
end
