class CreateRoutes < ActiveRecord::Migration[8.0]
  def change
    create_table :rails_pulse_routes do |t|
      t.string :method, null: false, comment: "HTTP method (e.g., GET, POST)"
      t.string :path, null: false, comment: "Request path (e.g., /posts/index)"

      t.timestamps
    end

    # Ensure unique constraint on method and path combination
    add_index :rails_pulse_routes, [:method, :path], unique: true, name: 'index_rails_pulse_routes_on_method_and_path'
  end
end
