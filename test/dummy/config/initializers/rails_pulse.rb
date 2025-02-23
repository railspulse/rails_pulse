RailsPulse.configure do |config|
  # ====================================================================================================
  #                                         GLOBAL CONFIGURATION
  # ====================================================================================================

  # Enable or disable Rails Pulse
  config.enabled = true

  # ====================================================================================================
  #                                               THRESHOLDS
  # ====================================================================================================
  # These thresholds are used to determine if a route, request, or query is slow, very slow, or critical.
  # Values are in milliseconds (ms). Adjust these based on your application's performance requirements.

  # Thresholds for an individual route
  config.route_thresholds = {
    slow:      500,
    very_slow: 1500,
    critical:  3000
  }

  # Thresholds for an individual request
  config.request_thresholds = {
    slow:      700,
    very_slow: 2000,
    critical:  4000
  }

  # Thresholds for an individual database query
  config.query_thresholds = {
    slow:      100,
    very_slow: 500,
    critical:  1000
  }

  # ====================================================================================================
  #                                               FILTERING
  # ====================================================================================================
  # Specify routes, requests, or queries to ignore from performance tracking.
  # Each array can include strings (exact matches) or regular expressions.
  #
  # Examples:
  #   config.ignored_routes   = ["/health_check", %r{^/admin}]
  #   config.ignored_requests = ["GET /status", %r{POST /api/v1/.*}]
  #   config.ignored_queries  = ["SELECT 1", %r{FROM \"schema_migrations\"}]

  config.ignored_routes   = []
  config.ignored_requests = []
  config.ignored_queries  = []

  # ====================================================================================================
  #                                               ARCHIVING
  # ====================================================================================================
  # Configure how long performance reports are kept before being deleted.
  # You can specify a time duration (e.g., 2.days, 1.week) and/or a maximum database size (in MB).
  # If both are set, archiving will occur when either condition is met.
  #
  # Examples:
  #   config.full_retention_period = 7.days      # Keep reports for 7 days
  #   config.max_database_size_mb  = 500         # Archive/delete when DB exceeds 500 MB
  #
  # Set to nil to disable a limit.

  # Time-based retention
  config.full_retention_period = 2.days

  # Size-based retention (set to an integer for MB limit)
  config.max_database_size_mb = nil
end
