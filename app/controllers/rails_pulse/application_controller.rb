module RailsPulse
  class ApplicationController < ActionController::Base
    include PaginationConcern
    include SessionFiltersConcern

    before_action :authenticate_rails_pulse_user!
    before_action :set_onboarding_state

    def set_global_filters
      if params[:clear] == "true"
        session.delete(:global_filters)
        session[:show_non_tagged] = true  # Reset show_non_tagged to default
      else
        filters = session[:global_filters] || {}

        # Update time filters if provided
        if params[:start_time].present? && params[:end_time].present?
          filters["start_time"] = params[:start_time]
          filters["end_time"] = params[:end_time]
        end

        # Update performance threshold if provided (or remove if empty)
        if params[:performance_threshold].present?
          filters["performance_threshold"] = params[:performance_threshold]
        else
          filters.delete("performance_threshold")
        end

        # Update tag visibility - convert enabled tags to disabled tags
        all_tags = RailsPulse.configuration.tags
        enabled_tags = params[:enabled_tags] || []

        # Handle "non_tagged" separately
        session[:show_non_tagged] = enabled_tags.include?("non_tagged")
        enabled_tags = enabled_tags - [ "non_tagged" ]

        disabled_tags = all_tags - enabled_tags

        if disabled_tags.any?
          filters["disabled_tags"] = disabled_tags
        else
          filters.delete("disabled_tags")
        end

        session[:global_filters] = filters
      end

      # Redirect back to the referring page or root
      redirect_back(fallback_location: root_path)
    end

    def set_time_range
      if params[:preset].present?
        # Store preset selection
        session[:time_range_preference] = params[:preset]
      elsif params[:start_time].present? && params[:end_time].present?
        # Store custom range
        session[:time_range_preference] = {
          type: "custom",
          start_time: params[:start_time],
          end_time: params[:end_time]
        }
      end

      # Redirect back to the referring page or root
      redirect_back(fallback_location: root_path)
    end

    private

    def logger
      RailsPulse.logger
    end

    def authenticate_rails_pulse_user!
      return unless RailsPulse.configuration.authentication_enabled

      # If no authentication method is configured, use fallback HTTP Basic Auth
      if RailsPulse.configuration.authentication_method.nil?
        return fallback_http_basic_auth
      end

      # Safely execute authentication method in controller context
      case RailsPulse.configuration.authentication_method
      when Proc
        instance_exec(&RailsPulse.configuration.authentication_method)
      when Symbol, String
        method_name = RailsPulse.configuration.authentication_method.to_s
        if respond_to?(method_name, true)
          send(method_name)
        else
          logger.error "RailsPulse: Authentication method '#{method_name}' not found"
          render plain: "Authentication configuration error", status: :internal_server_error
        end
      else
        logger.error "RailsPulse: Invalid authentication method type: #{RailsPulse.configuration.authentication_method.class}"
        render plain: "Authentication configuration error", status: :internal_server_error
      end
    rescue StandardError => e
      logger.warn "RailsPulse authentication failed: #{e.message}"
      redirect_to RailsPulse.configuration.authentication_redirect_path
    end

    def fallback_http_basic_auth
      authenticate_or_request_with_http_basic("Rails Pulse") do |username, password|
        # Use environment variables for default credentials
        expected_username = ENV.fetch("RAILS_PULSE_USERNAME", "admin")
        expected_password = ENV.fetch("RAILS_PULSE_PASSWORD", nil)

        if expected_password.nil?
          logger.error "RailsPulse: No authentication method configured and RAILS_PULSE_PASSWORD not set. Access denied."
          false
        else
          username == expected_username && password == expected_password
        end
      end
    end

    def set_onboarding_state
      @has_requests = RailsPulse::Request.exists?
      last_summary_at = RailsPulse::Summary.maximum(:updated_at)
      @has_summaries = last_summary_at.present?
      @summaries_stale = RailsPulse.configuration.warn_on_stale_summaries && @has_summaries && last_summary_at < 2.hours.ago
    end
  end
end
