class AddTagsToRailsPulseTables < ActiveRecord::Migration[7.0]
  def change
    add_column :rails_pulse_routes, :tags, :text unless column_exists?(:rails_pulse_routes, :tags)
    add_column :rails_pulse_queries, :tags, :text unless column_exists?(:rails_pulse_queries, :tags)
    add_column :rails_pulse_requests, :tags, :text unless column_exists?(:rails_pulse_requests, :tags)
  end
end
