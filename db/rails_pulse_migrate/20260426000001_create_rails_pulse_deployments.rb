# Add rails_pulse_deployments table for tracking deployment events
class CreateRailsPulseDeployments < ActiveRecord::Migration[7.0]
  def up
    unless table_exists?(:rails_pulse_deployments)
      create_table :rails_pulse_deployments do |t|
        t.string   :revision,    null: false, comment: "Git SHA, tag, or version string"
        t.datetime :started_at,  null: false, comment: "When the deployment started"
        t.datetime :finished_at,             comment: "When the deployment finished (nil if still in progress or unknown)"
        t.text     :metadata,                comment: "JSON object of arbitrary deployment metadata"
        t.timestamps
      end

      add_index :rails_pulse_deployments, :started_at,
        name: "index_rails_pulse_deployments_on_started_at"
      add_index :rails_pulse_deployments, :revision,
        name: "index_rails_pulse_deployments_on_revision"
    end
  end

  def down
    drop_table :rails_pulse_deployments if table_exists?(:rails_pulse_deployments)
  end
end
