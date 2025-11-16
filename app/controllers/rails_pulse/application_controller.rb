module RailsPulse
  class ApplicationController < ActionController::Base
    # Support both Pagy 8.x (Backend) and Pagy 43+ (Method)
    if defined?(Pagy::Method)
      include Pagy::Method
    else
      include Pagy::Backend
    end

    before_action :authenticate_rails_pulse_user!
    before_action :set_show_non_tagged_default
    helper_method :session_global_filters, :session_disabled_tags

    def set_pagination_limit(limit = nil)
      limit = limit || params[:limit]
      session[:pagination_limit] = limit.to_i if limit.present?

    # Render JSON for direct API calls or AJAX requests (but not turbo frame requests)
    if (request.xhr? && !turbo_frame_request?) || (request.patch? && action_name == "set_pagination_limit")
        render json: { status: "ok" }
    end
    end

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

    def session_global_filters
      session[:global_filters] || {}
    end

    def session_disabled_tags
      session_global_filters["disabled_tags"] || []
    end

    # Get the minimum duration based on global performance threshold
    # Returns nil if no threshold is set (show all)
    # context: :route, :request, or :query
    def global_performance_threshold_duration(context)
      threshold = session_global_filters["performance_threshold"]
      return nil unless threshold.present?

      config_key = "#{context}_thresholds".to_sym
      thresholds = RailsPulse.configuration.public_send(config_key)

      thresholds[threshold.to_sym]
    rescue StandardError => e
      Rails.logger.warn "Failed to get performance threshold: #{e.message}"
      nil
    end

    # Set default value for show_non_tagged if not already set
    def set_show_non_tagged_default
      session[:show_non_tagged] = true if session[:show_non_tagged].nil?
    end

    # Returns Pagy options hash with correct parameter name for current version
    # Pagy 8.x uses 'items:', Pagy 43+ uses 'limit:'
    def pagy_options(count)
      if defined?(Pagy::Method)
        { limit: count }  # Pagy 43+
      else
        { items: count }  # Pagy 8.x
      end
    end
  end
end
