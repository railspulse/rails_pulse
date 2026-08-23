class AddControllerActionToRailsPulseRoutes < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:rails_pulse_routes, :controller_action)
      add_column :rails_pulse_routes, :controller_action, :string,
        comment: "Rails controller and action handling this route (e.g., admin/users#show)"
    end
  end
end
