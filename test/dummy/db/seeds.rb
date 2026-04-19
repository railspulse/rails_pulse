# Rails Pulse Seed Data Generator
#
# Environment Variables:
#
# SEED_MODE                        Preset configuration (default: quick)
#   - quick:   7 days, 1000 requests, minimal backfill (fast, no warnings)
#   - demo:    14 days, 5000 requests, complete backfill (thorough)
#   - testing: 35 days, 10000 requests, no backfill (triggers warnings)
#   - custom:  Use individual options below
#
# Individual Options (override SEED_MODE):
#   HISTORICAL_DAYS=<n>            Days of historical data (default: mode default)
#   HISTORICAL_REQUEST_COUNT=<n>   Number of requests to generate (default: mode default)
#   SUMMARY_STRATEGY=<strategy>    How to backfill summaries:
#     - none:     No backfill (fast, may trigger warnings)
#     - minimal:  Last 26 hours only (default for quick mode)
#     - smart:    Cover retention period (~14 days)
#     - complete: Full historical range (slowest, thorough)
#
# Legacy:
#   AUTO_BACKFILL_SUMMARIES=true   Force complete strategy (overrides SUMMARY_STRATEGY)
#
# Examples:
#   rails db:seed                                           # Quick mode (default)
#   SEED_MODE=demo rails db:seed                            # Demo preset
#   SEED_MODE=custom HISTORICAL_DAYS=21 SUMMARY_STRATEGY=smart rails db:seed
#   HISTORICAL_DAYS=0 rails db:seed                         # Skip historical data entirely

# Load support files
require_relative "seeds/support/seed_config"
require_relative "seeds/support/seed_helpers"
require_relative "seeds/base_data"
require_relative "seeds/statistics"

# Display database connection info
SeedConfig.display_db_info

# Create base application data (users, posts, comments)
BaseData.seed!

# Generate historical Rails Pulse performance data
require_relative "seeds/rails_pulse/historical_data"
RailsPulse::Seeds::HistoricalData.seed! unless SeedConfig.days_ago == 0

# Display statistics
Statistics.display!
