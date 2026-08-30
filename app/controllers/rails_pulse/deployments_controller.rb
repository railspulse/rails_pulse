module RailsPulse
  class DeploymentsController < ApplicationController
    skip_before_action :authenticate_rails_pulse_user!
    skip_before_action :verify_authenticity_token, only: %i[create finish]
    before_action :authenticate_deployment_request!

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

    def finish
      deployment = RailsPulse::Deployment
        .where(revision: finish_params[:revision])
        .order(started_at: :desc)
        .first

      return render json: { status: "error", error: "Deployment not found" }, status: :not_found unless deployment

      deployment.finished_at = finish_params[:finished_at].presence || Time.current

      if deployment.save
        render json: { status: "updated", id: deployment.id, revision: deployment.revision,
                       started_at: deployment.started_at, finished_at: deployment.finished_at }
      else
        render json: { status: "error", errors: deployment.errors.full_messages },
               status: :unprocessable_content
      end
    end

    private

    def authenticate_deployment_request!
      token = RailsPulse.configuration.deployment_api_token
      if token.present?
        provided = request.headers["X-Rails-Pulse-Token"].to_s
        unless ActiveSupport::SecurityUtils.secure_compare(provided, token)
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      elsif RailsPulse.configuration.authentication_enabled
        authenticate_rails_pulse_user!
      else
        # No token configured and authentication disabled — fail closed.
        # Without a token there is no way to verify the caller.
        render json: { error: "Unauthorized — set deployment_api_token or enable authentication" }, status: :unauthorized
      end
    end

    def deployment_params
      params.require(:deployment).permit(:revision, :started_at, :finished_at, metadata: {})
    end

    def finish_params
      params.require(:deployment).permit(:revision, :finished_at)
    end
  end
end
