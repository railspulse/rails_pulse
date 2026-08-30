require "rails_pulse/route_indexes"

class AddNullActionUniqueIndexToRoutes < ActiveRecord::Migration[7.0]
  def up
    if duplicate_null_action_paths?
      say "Deferring null-action unique index — duplicate paths exist."
      say "Run `rails rails_pulse:migrate_routes` to consolidate duplicates, then"
      say "the index will be created automatically."
      return
    end

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
