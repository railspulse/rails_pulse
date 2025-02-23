class CreateRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :rails_pulse_requests do |t|
      t.references :route, null: false, foreign_key: { to_table: :rails_pulse_routes }, comment: "Link to the route"
      t.decimal :duration, precision: 10, scale: 6, null: false, comment: "Total request duration in milliseconds"
      t.integer :status, null: false, comment: "HTTP status code (e.g., 200, 500)"
      t.boolean :is_error, null: false, default: false, comment: "True if status >= 500"
      t.string :request_uuid, null: false, comment: "Unique identifier for the request (e.g., UUID)"
      t.string :controller_action, comment: "Controller and action handling the request (e.g., PostsController#show)"
      t.timestamp :occurred_at, null: false, comment: "When the request started"

      t.timestamps
    end

    add_index :rails_pulse_requests, :occurred_at, name: 'index_rails_pulse_requests_on_occurred_at'
    add_index :rails_pulse_requests, :request_uuid, unique: true, name: 'index_rails_pulse_requests_on_request_uuid'
    # add_index :rails_pulse_requests, :route_id, name: 'index_rails_pulse_requests_on_route_id'
  end
end
