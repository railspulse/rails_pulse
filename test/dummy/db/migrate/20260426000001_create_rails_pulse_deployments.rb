# Add rails_pulse_deployments table for tracking deployment events
class CreateRailsPulseDeployments < ActiveRecord::Migration[7.0]
  def up
    unless table_exists?(:rails_pulse_deployments)
      create_table :rails_pulse_deployments do |t|
        t.string   :revision,    null: false, comment: "Git SHA, tag, or version string"
        t.datetime :deployed_at, null: false, comment: "When the deployment occurred"
        t.text     :metadata,                 comment: "JSON object of arbitrary deployment metadata"
        t.timestamps
      end

      add_index :rails_pulse_deployments, :deployed_at,
        name: "index_rails_pulse_deployments_on_deployed_at"
      add_index :rails_pulse_deployments, :revision,
        name: "index_rails_pulse_deployments_on_revision"
    end
  end

  def down
    drop_table :rails_pulse_deployments if table_exists?(:rails_pulse_deployments)
  end
end
