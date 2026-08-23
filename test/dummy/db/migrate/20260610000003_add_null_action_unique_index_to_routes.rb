require "rails_pulse/route_indexes"

class AddNullActionUniqueIndexToRoutes < ActiveRecord::Migration[7.0]
  def up
    return if duplicate_null_action_paths?

    RailsPulse::RouteIndexes.ensure_null_action_uniqueness!(connection)
  end

  def down
    RailsPulse::RouteIndexes.remove_null_action_uniqueness!(connection)
  end

  private

  def duplicate_null_action_paths?
    connection.select_value(<<~SQL).to_i.positive?
      SELECT COUNT(*) FROM (
        SELECT 1
        FROM rails_pulse_routes
        WHERE controller_action IS NULL
        GROUP BY path
        HAVING COUNT(*) > 1
      ) duplicates
    SQL
  end
end
