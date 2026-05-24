class AddActualQueryToOperations < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:rails_pulse_operations, :actual_sql)
      add_column :rails_pulse_operations, :actual_sql, :text,
        comment: "Actual SQL that ran for sql operations — comment-stripped, unparameterized, unbounded"
    end

    return unless table_exists?(:rails_pulse_operations)

    # Backfill actual_sql from label for existing sql operations.
    # NOTE: On MySQL installations that hit the 255-char truncation bug,
    # actual_sql will contain a partial SQL string — the full query is unrecoverable.
    # The associated query.normalized_sql is unaffected and analysis still works.
    RailsPulse::Operation
      .where(operation_type: "sql", actual_sql: nil)
      .in_batches(of: 1000) do |batch|
        batch.update_all("actual_sql = label")
      end
  end

  def down
    remove_column :rails_pulse_operations, :actual_sql if column_exists?(:rails_pulse_operations, :actual_sql)
  end
end
