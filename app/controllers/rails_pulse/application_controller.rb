module RailsPulse
  class ApplicationController < ActionController::Base
    before_action :authenticate_rails_pulse_user!

    def set_pagination_limit(limit = nil)
      limit = limit || params[:limit]
      session[:pagination_limit] = limit.to_i if limit.present?

      # Render JSON for direct API calls or AJAX requests (but not turbo frame requests)
      if (request.xhr? && !turbo_frame_request?) || (request.patch? && action_name == "set_pagination_limit")
        render json: { status: "ok" }
      end
    end

    private

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
          Rails.logger.error "RailsPulse: Authentication method '#{method_name}' not found"
          render plain: "Authentication configuration error", status: :internal_server_error
        end
      else
        Rails.logger.error "RailsPulse: Invalid authentication method type: #{RailsPulse.configuration.authentication_method.class}"
        render plain: "Authentication configuration error", status: :internal_server_error
      end
    rescue StandardError => e
      Rails.logger.warn "RailsPulse authentication failed: #{e.message}"
      redirect_to RailsPulse.configuration.authentication_redirect_path
    end

    def fallback_http_basic_auth
      authenticate_or_request_with_http_basic("Rails Pulse") do |username, password|
        # Use environment variables for default credentials
        expected_username = ENV.fetch("RAILS_PULSE_USERNAME", "admin")
        expected_password = ENV.fetch("RAILS_PULSE_PASSWORD", nil)

        if expected_password.nil?
          Rails.logger.error "RailsPulse: No authentication method configured and RAILS_PULSE_PASSWORD not set. Access denied."
          false
        else
          username == expected_username && password == expected_password
        end
      end
    end

    def session_pagination_limit
      # Use URL param if present, otherwise session, otherwise default
      limit = params[:limit].presence || session[:pagination_limit] || 10
      # Update session if URL param was used
      session[:pagination_limit] = limit.to_i if params[:limit].present?
      limit.to_i
    end

    def store_pagination_limit(limit)
      # Validate pagination limit: minimum 5, maximum 50 for performance
      validated_limit = limit.to_i.clamp(5, 50)
      session[:pagination_limit] = validated_limit if limit.present?
    end
  end
end
