# Upgrade Rails Pulse tables with new features
class UpgradeRailsPulseTables < ActiveRecord::Migration[<%= @migration_version %>]
  def change
    <% @missing_columns.each do |table_name, columns| %>
      <% columns.each do |column_name, definition| %>
    # Add <%= column_name %> column to <%= table_name %>
    add_column :<%= table_name %>, :<%= column_name %>, :<%= definition[:type] %><% if definition[:comment] %>, comment: "<%= definition[:comment] %>"<% end %>
      <% end %>
    <% end %>
  end

  def down
    <% @missing_columns.each do |table_name, columns| %>
      <% columns.each do |column_name, _definition| %>
    remove_column :<%= table_name %>, :<%= column_name %>
      <% end %>
    <% end %>
  end
end