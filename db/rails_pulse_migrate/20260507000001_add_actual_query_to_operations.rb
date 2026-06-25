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
    #
    # Uses execute() rather than the model so the backfill runs on the migration's own
    # connection and sees the column added above, even on separate-database setups where
    # RailsPulse::ApplicationRecord uses a different connection pool (SQLite keeps DDL
    # inside the open transaction, so a second pool cannot see the new column).
    execute(<<~SQL)
      UPDATE rails_pulse_operations
      SET actual_sql = label
      WHERE operation_type = 'sql' AND actual_sql IS NULL
    SQL
  end

  def down
    remove_column :rails_pulse_operations, :actual_sql if column_exists?(:rails_pulse_operations, :actual_sql)
  end
end
