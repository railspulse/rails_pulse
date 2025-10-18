class AddTagsToRailsPulseTables < ActiveRecord::Migration[7.0]
  def change
    add_column :rails_pulse_routes, :tags, :text, comment: "JSON array of tags for filtering and categorization" unless column_exists?(:rails_pulse_routes, :tags)
    add_column :rails_pulse_queries, :tags, :text, comment: "JSON array of tags for filtering and categorization" unless column_exists?(:rails_pulse_queries, :tags)
    add_column :rails_pulse_requests, :tags, :text, comment: "JSON array of tags for filtering and categorization" unless column_exists?(:rails_pulse_requests, :tags)
  end
end
