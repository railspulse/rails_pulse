module RailsPulse
  class Configuration
    attr_accessor :enabled,
                  :route_thresholds,
                  :request_thresholds,
                  :query_thresholds,
                  :job_thresholds,
                  :ignored_routes,
                  :ignored_requests,
                  :ignored_queries,
                  :ignored_jobs,
                  :ignored_queues,
                  :track_assets,
                  :track_jobs,
                  :custom_asset_patterns,
                  :mount_path,
                  :full_retention_period,
                  :archiving_enabled,
                  :max_table_records,
                  :connects_to,
                  :authentication_enabled,
                  :authentication_method,
                  :authentication_redirect_path,
                  :tags,
                  :job_tracking_mode,
                  :job_adapters,
                  :capture_job_arguments,
                  :mount_dashboard,
                  :logger,
                  :async,
                  :service_level_objectives,
                  :query_service_level_objectives,
                  :warn_on_stale_summaries

    def initialize
      @enabled = true
      @route_thresholds = { slow: 500, very_slow: 1500, critical: 3000 }
      @request_thresholds = { slow: 700, very_slow: 2000, critical: 4000 }
      @query_thresholds = { slow: 100, very_slow: 500, critical: 1000 }
      @job_thresholds = { slow: 5_000, very_slow: 30_000, critical: 60_000 }
      @ignored_routes = []
      @ignored_requests = []
      @ignored_queries = []
      @ignored_jobs = []
      @ignored_queues = []
      @track_assets = false
      @track_jobs = false
      @custom_asset_patterns = []
      @mount_path = nil
      @full_retention_period = 30.days
      @archiving_enabled = true
      @max_table_records = {
        rails_pulse_operations: 100_000,
        rails_pulse_requests: 50_000,
        rails_pulse_job_runs: 50_000,
        rails_pulse_queries: 10_000,
        rails_pulse_routes: 1_000,
        rails_pulse_jobs: 1_000
      }
      @connects_to = nil
      @authentication_enabled = Rails.env.production?
      @authentication_method = nil
      @authentication_redirect_path = "/"
      @tags = [ "ignored", "critical", "experimental" ]
      @job_tracking_mode = :universal
      @job_adapters = {
        sidekiq: { enabled: true, track_queue_depth: false },
        solid_queue: { enabled: true, track_recurring: false },
        good_job: { enabled: true, track_cron: false },
        delayed_job: { enabled: true },
        resque: { enabled: true }
      }
      @capture_job_arguments = false

      # Dashboard settings
      @mount_dashboard = true
      @logger = nil

      # Tracking mode settings
      @async = true

      # Service Level Objectives (default: [] = no SLOs configured)
      @service_level_objectives = []
      @query_service_level_objectives = []

      # Show a warning banner when summaries haven't been generated recently
      @warn_on_stale_summaries = true

      # Validate defaults eagerly so that a misconfigured initializer raises at
      # boot time rather than at the first request. All SLO defaults are nil so
      # validation short-circuits harmlessly here; it becomes meaningful when
      # RailsPulse.configure yields and sets real values.
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
      validate_tags!
      validate_job_settings!
      validate_dashboard_settings!
      validate_tracking_settings!
      validate_service_level_objectives_settings!
      validate_query_service_level_objectives_settings!
    end

    private

    def validate_thresholds!
      [ @route_thresholds, @request_thresholds, @query_thresholds, @job_thresholds ].each do |thresholds|
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
        RailsPulse.logger.warn "Authentication is enabled but no authentication method is configured. This will deny all access."
      end

      if @authentication_method && ![ Proc, Symbol, String ].include?(@authentication_method.class)
        raise ArgumentError, "authentication_method must be a Proc, Symbol, String, or nil, got #{@authentication_method.class}"
      end
    end

    def validate_tags!
      unless @tags.is_a?(Array)
        raise ArgumentError, "tags must be an array, got #{@tags.class}"
      end

      @tags.each do |tag|
        unless tag.is_a?(String)
          raise ArgumentError, "tags must be strings, got #{tag.class}"
        end
      end
    end

    def validate_job_settings!
      unless @ignored_jobs.is_a?(Array) && @ignored_queues.is_a?(Array)
        raise ArgumentError, "ignored_jobs and ignored_queues must be arrays"
      end

      unless [ true, false ].include?(@track_jobs)
        raise ArgumentError, "track_jobs must be a boolean"
      end

      unless @job_adapters.is_a?(Hash)
        raise ArgumentError, "job_adapters must be a hash"
      end

      unless @job_thresholds.is_a?(Hash)
        raise ArgumentError, "job_thresholds must be a hash"
      end

      unless @job_tracking_mode.is_a?(Symbol)
        raise ArgumentError, "job_tracking_mode must be a symbol"
      end

      unless [ true, false ].include?(@capture_job_arguments)
        raise ArgumentError, "capture_job_arguments must be a boolean"
      end
    end

    def validate_dashboard_settings!
      unless [ true, false ].include?(@mount_dashboard)
        raise ArgumentError, "mount_dashboard must be true or false, got #{@mount_dashboard}"
      end
    end

    def validate_tracking_settings!
      unless [ true, false ].include?(@async)
        raise ArgumentError, "async must be true or false, got #{@async}"
      end
    end

    def validate_service_level_objectives_settings!
      unless @service_level_objectives.is_a?(Array)
        raise ArgumentError, "service_level_objectives must be an array, got #{@service_level_objectives.class}"
      end

      @service_level_objectives.each do |slo|
        validate_slo_entry!(slo, "service_level_objectives")
      end
    end

    def validate_query_service_level_objectives_settings!
      unless @query_service_level_objectives.is_a?(Array)
        raise ArgumentError, "query_service_level_objectives must be an array, got #{@query_service_level_objectives.class}"
      end

      @query_service_level_objectives.each do |slo|
        validate_slo_entry!(slo, "query_service_level_objectives")
      end
    end

    def validate_slo_entry!(slo, config_name)
      unless slo.is_a?(Hash)
        raise ArgumentError, "#{config_name} entries must be hashes with :percentile and :threshold keys, got #{slo.class}"
      end

      unless slo.key?(:percentile) && slo.key?(:threshold)
        raise ArgumentError, "#{config_name} entries must contain both :percentile and :threshold keys"
      end

      percentile = slo[:percentile]
      threshold = slo[:threshold]

      unless [ 95, 99 ].include?(percentile)
        raise ArgumentError, "#{config_name} entry :percentile must be 95 or 99, got #{percentile}"
      end

      unless threshold.is_a?(Numeric) && threshold > 0
        raise ArgumentError, "#{config_name} entry :threshold must be a positive number, got #{threshold}"
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
