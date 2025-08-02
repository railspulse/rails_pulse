# This migration comes from rails_pulse (originally 20250227235904)
class CreateRoutes < RailsPulse::Migration
  def change
    create_table :rails_pulse_routes do |t|
      t.string :method, null: false, comment: "HTTP method (e.g., GET, POST)"
      t.string :path, null: false, comment: "Request path (e.g., /posts/index)"

      t.timestamps
    end

    add_index :rails_pulse_routes, [ :method, :path ], unique: true, name: "index_rails_pulse_routes_on_method_and_path"
  end
end
