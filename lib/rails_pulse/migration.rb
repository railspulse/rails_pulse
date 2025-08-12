module RailsPulse
  # Determine the appropriate migration version based on Rails version
  migration_version = case Rails.version
  when /^8\./
    8.0
  when /^7\.2/
    7.2
  when /^7\.1/
    7.1
  when /^7\.0/
    7.0
  else
    7.1 # Default fallback
  end

  class Migration < ActiveRecord::Migration[migration_version]
    # This base migration class ensures that Rails Pulse migrations
    # target the correct database when using multiple database configuration.
    # The connection is determined by the connects_to configuration.

    def connection
      if RailsPulse.connects_to
        RailsPulse::ApplicationRecord.connection
      else
        super
      end
    end
  end
end
