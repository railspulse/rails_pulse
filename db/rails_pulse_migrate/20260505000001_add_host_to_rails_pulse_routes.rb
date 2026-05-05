class AddHostToRailsPulseRoutes < ActiveRecord::Migration[7.2]
  def up
    create_table :rails_pulse_hosts do |t|
      t.string :name, null: false, comment: "Hostname (e.g., example.com)"
      t.timestamps
    end

    add_index :rails_pulse_hosts, :name, unique: true, name: "index_rails_pulse_hosts_on_name"

    add_reference :rails_pulse_routes, :host, foreign_key: { to_table: :rails_pulse_hosts }, comment: "Link to the host"

    # Replace the old unique index with one that includes host_id
    remove_index :rails_pulse_routes, name: "index_rails_pulse_routes_on_method_and_path"
    add_index :rails_pulse_routes, [:method, :path, :host_id], unique: true, name: "index_rails_pulse_routes_on_method_path_and_host"

    # Existing routes will have host_id = NULL. This is intentional — the host
    # wasn't tracked before this migration. New requests will auto-create hosts.
    # To backfill existing routes, run: rails rails_pulse:backfill_hosts[example.com]
  end

  def down
    remove_index :rails_pulse_routes, name: "index_rails_pulse_routes_on_method_path_and_host"

    # Deduplicate routes that share method+path (keep lowest id)
    execute <<~SQL
      DELETE FROM rails_pulse_routes
      WHERE id NOT IN (
        SELECT MIN(id) FROM rails_pulse_routes GROUP BY method, path
      )
    SQL

    add_index :rails_pulse_routes, [:method, :path], unique: true, name: "index_rails_pulse_routes_on_method_and_path"
    remove_reference :rails_pulse_routes, :host, foreign_key: { to_table: :rails_pulse_hosts }
    drop_table :rails_pulse_hosts
  end
end
