module RailsPulse
  class Configuration
    attr_accessor :enabled,
                  :route_thresholds,
                  :request_thresholds,
                  :query_thresholds,
                  :ignored_routes,
                  :ignored_requests,
                  :ignored_queries,
                  :track_assets,
                  :custom_asset_patterns,
                  :mount_path,
                  :full_retention_period,
                  :archiving_enabled,
                  :max_table_records,
                  :connects_to,
                  :authentication_enabled,
                  :authentication_method,
                  :authentication_redirect_path

    def initialize
      @enabled = true
      @route_thresholds = { slow: 500, very_slow: 1500, critical: 3000 }
      @request_thresholds = { slow: 700, very_slow: 2000, critical: 4000 }
      @query_thresholds = { slow: 100, very_slow: 500, critical: 1000 }
      @ignored_routes = []
      @ignored_requests = []
      @ignored_queries = []
      @track_assets = false
      @custom_asset_patterns = []
      @mount_path = nil
      @full_retention_period = 2.weeks
      @archiving_enabled = true
      @max_table_records = {
        rails_pulse_requests: 10000,
        rails_pulse_operations: 50000,
        rails_pulse_routes: 1000,
        rails_pulse_queries: 500
      }
      @connects_to = nil
      @authentication_enabled = Rails.env.production?
      @authentication_method = nil
      @authentication_redirect_path = "/"

      validate_configuration!
    end

    # Get all routes to ignore, including asset patterns if track_assets is false
    def ignored_routes
      routes = @ignored_routes.dup

      unless @track_assets
        routes.concat(default_asset_patterns)
        routes.concat(@custom_asset_patterns)
      end

      routes
    end

    # Validate configuration settings
    def validate_configuration!
      validate_thresholds!
      validate_retention_settings!
      validate_patterns!
      validate_database_settings!
      validate_authentication_settings!
    end

    # Revalidate configuration after changes
    def revalidate!
      validate_configuration!
    end

    private

    def validate_thresholds!
      [ @route_thresholds, @request_thresholds, @query_thresholds ].each do |thresholds|
        thresholds.each do |key, value|
          unless value.is_a?(Numeric) && value > 0
            raise ArgumentError, "Threshold #{key} must be a positive number, got #{value}"
          end
        end
      end
    end

    def validate_retention_settings!
      unless @full_retention_period.respond_to?(:seconds)
        raise ArgumentError, "full_retention_period must be a time duration (e.g., 2.weeks), got #{@full_retention_period}"
      end

      @max_table_records.each do |table, count|
        unless count.is_a?(Integer) && count > 0
          raise ArgumentError, "max_table_records[#{table}] must be a positive integer, got #{count}"
        end
      end
    end

    def validate_patterns!
      [ @ignored_routes, @ignored_requests, @ignored_queries, @custom_asset_patterns ].each do |patterns|
        patterns.each do |pattern|
          unless pattern.is_a?(String) || pattern.is_a?(Regexp)
            raise ArgumentError, "Ignored patterns must be strings or regular expressions, got #{pattern.class}"
          end

          # Test regex patterns to ensure they're valid
          if pattern.is_a?(Regexp)
            begin
              "test" =~ pattern
            rescue RegexpError => e
              raise ArgumentError, "Invalid regular expression pattern: #{e.message}"
            end
          end
        end
      end
    end

    def validate_database_settings!
      if @connects_to && !@connects_to.is_a?(Hash)
        raise ArgumentError, "connects_to must be a hash with database connection configuration"
      end
    end

    def validate_authentication_settings!
      if @authentication_enabled && @authentication_method.nil?
        # Use Rails.logger if available, otherwise fall back to puts (for asset precompilation)
        if Rails.logger
          Rails.logger.warn "RailsPulse: Authentication is enabled but no authentication method is configured. This will deny all access."
        else
          puts "RailsPulse: Authentication is enabled but no authentication method is configured. This will deny all access."
        end
      end

      if @authentication_method && ![ Proc, Symbol, String, NilClass ].include?(@authentication_method.class)
        raise ArgumentError, "authentication_method must be a Proc, Symbol, String, or nil, got #{@authentication_method.class}"
      end
    end

    # Default patterns for common asset types and paths
    def default_asset_patterns
      [
        # Asset file extensions
        %r{\.(png|jpg|jpeg|gif|svg|css|js|ico|woff|woff2|ttf|eot|map)$}i,

        # Common Rails asset paths
        %r{^/assets/},
        %r{^/packs/},
        %r{^/.*?/assets/},  # Catches /connect/assets/, /admin/assets/, etc.

        # Webpack dev server
        %r{^/__webpack_hmr},
        %r{^/sockjs-node/},

        # Common health check endpoints
        "/health",
        "/health_check",
        "/status",
        "/ping",

        # Favicon requests
        "/favicon.ico",
        "/apple-touch-icon.png",
        "/apple-touch-icon-precomposed.png",

        # Robots and sitemaps
        "/robots.txt",
        "/sitemap.xml"
      ]
    end
  end
end
