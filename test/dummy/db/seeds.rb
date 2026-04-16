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
if ENV["GENERATE_HISTORICAL_DATA"] == "true"
  require_relative "seeds/rails_pulse/historical_data"
  RailsPulse::Seeds::HistoricalData.seed!
end

# Display statistics
Statistics.display!
