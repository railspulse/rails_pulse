class MakeCacheHitOnOperationsNullable < ActiveRecord::Migration[7.0]
  def change
    return unless column_exists?(:rails_pulse_operations, :cache_hit)

    change_column_null :rails_pulse_operations, :cache_hit, true
    change_column_default :rails_pulse_operations, :cache_hit, from: false, to: nil
  end
end
