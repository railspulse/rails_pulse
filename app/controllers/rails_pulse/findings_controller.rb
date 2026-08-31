module RailsPulse
  # Findings are written by FindingDetector once a day. This is where they live
  # — the surface that turns "we detected a regression" into something a person
  # can read, act on, and dismiss.
  class FindingsController < ApplicationController
    before_action :set_finding, only: %i[show update]

    def index
      ransack_params = (params[:q] || {}).dup
      apply_default_status_filter!(ransack_params)

      @ransack_query = Finding.ransack(ransack_params)
      @ransack_query.sorts = "last_detected_at desc" if @ransack_query.sorts.empty?

      @pagination, @table_data = paginate(@ransack_query.result, limit: session_pagination_limit)
      @deployments = DeploymentCorrelator.for_all(@table_data)
      @counts = status_counts
    end

    def show
      @deployment = DeploymentCorrelator.for(@finding)
    end

    # Acknowledge or reopen. Resolution is not a manual action: a finding is
    # resolved when detection stops seeing it, so letting a user mark one
    # resolved by hand would produce a row the next detection run immediately
    # contradicts.
    def update
      case params[:status]
      when "acknowledged"
        @finding.update!(status: "acknowledged")
        notice = "Finding acknowledged."
      when "open"
        @finding.update!(status: "open")
        notice = "Finding reopened."
      else
        return redirect_to finding_path(@finding), alert: "Unknown action."
      end

      redirect_to finding_path(@finding), notice: notice
    end

    private

    def set_finding
      @finding = Finding.find(params[:id])
    end

    # Default to what is still live. A resolved finding is history, and the list
    # is more useful as a description of the present.
    def apply_default_status_filter!(ransack_params)
      return if ransack_params.key?(:status_eq) || ransack_params.key?("status_eq")

      ransack_params[:status_eq] = "open"
    end

    def status_counts
      Finding.group(:status).count
    end
  end
end
