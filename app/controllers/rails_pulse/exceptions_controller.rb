module RailsPulse
  class ExceptionsController < ApplicationController
    before_action :set_exception_group, only: %i[show update]

    def index
      ransack_params = (params[:q] || {}).dup
      apply_default_status_filter!(ransack_params)

      @ransack_query = ExceptionGroup.ransack(ransack_params)
      @ransack_query.sorts = "last_seen_at desc" if @ransack_query.sorts.empty?
      @pagination, @table_data = paginate(@ransack_query.result, limit: session_pagination_limit)
    end

    def show
      occurrences = @exception_group.occurrences.order(occurred_at: :desc)
      @latest_occurrence = occurrences.first
      @pagination, @occurrences = paginate(occurrences, limit: session_pagination_limit)
    end

    def update
      if params.key?(:preserve)
        update_preserve
      else
        update_status
      end
    end

    private

    def set_exception_group
      @exception_group = ExceptionGroup.find(params[:id])
    end

    # Default the list to open groups. An explicit blank status ("All")
    # clears the filter; any other value is passed through to ransack.
    def apply_default_status_filter!(ransack_params)
      if !ransack_params.key?(:status_eq) && !ransack_params.key?("status_eq")
        ransack_params[:status_eq] = "open"
      elsif ransack_params[:status_eq].blank? && ransack_params["status_eq"].blank?
        ransack_params.delete(:status_eq)
        ransack_params.delete("status_eq")
      end
    end

    def update_preserve
      @exception_group.update!(preserve: ActiveModel::Type::Boolean.new.cast(params[:preserve]))
      flash[:notice] = @exception_group.preserve? ? "Exception preserved from cleanup." : "Exception no longer preserved."
      redirect_to exception_path(@exception_group)
    end

    def update_status
      new_status = params[:status]
      unless ExceptionGroup::STATUSES.include?(new_status)
        head :unprocessable_entity
        return
      end

      @exception_group.update!(
        status: new_status,
        resolved_at: new_status == "resolved" ? Time.current : nil
      )

      flash[:notice] = "Exception marked as #{new_status}."
      redirect_to exception_path(@exception_group)
    end
  end
end
