class AddDiagnosticFields < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:rails_pulse_operations, :row_count)
      add_column :rails_pulse_operations, :row_count, :integer
    end
    unless column_exists?(:rails_pulse_operations, :cache_hit)
      add_column :rails_pulse_operations, :cache_hit, :boolean, null: false, default: false
    end
    unless column_exists?(:rails_pulse_operations, :repeated_query_group)
      add_column :rails_pulse_operations, :repeated_query_group, :text
    end
    unless column_exists?(:rails_pulse_operations, :repetition_count)
      add_column :rails_pulse_operations, :repetition_count, :integer
    end
    unless column_exists?(:rails_pulse_requests, :response_size_bytes)
      add_column :rails_pulse_requests, :response_size_bytes, :integer
    end
  end
end
