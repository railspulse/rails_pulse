module RailsPulse
  class Migration < ActiveRecord::Migration[7.1]
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
