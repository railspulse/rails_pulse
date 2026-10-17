class CreateRailsPulseRollups < ActiveRecord::Migration[7.0]
  def change
    return if table_exists?(:rails_pulse_rollups)

    create_table :rails_pulse_rollups do |t|
      # Per-writer per-hour aggregates of the requests and SQL operations that
      # config.store_full_details folded instead of persisting
      t.references :rollupable, polymorphic: true, null: false, index: false, comment: "Link to Route or Query"
      t.datetime :period_start, null: false, comment: "Start of the hour the folded requests occurred in"
      t.string :writer_id, null: false, comment: "host:pid:uuid of the writer incarnation that owns the row"

      t.integer :count, default: 0, null: false, comment: "Folded requests (route rows) or operations (query rows)"
      t.integer :error_count, default: 0, null: false, comment: "Folded 5xx requests; always 0 on query rows"
      t.integer :status_2xx, default: 0, null: false, comment: "Folded 2xx responses; always 0 on query rows"
      t.integer :status_3xx, default: 0, null: false, comment: "Folded 3xx responses; always 0 on query rows"
      t.integer :status_4xx, default: 0, null: false, comment: "Folded 4xx responses; always 0 on query rows"
      t.integer :status_5xx, default: 0, null: false, comment: "Folded 5xx responses; always 0 on query rows"

      t.decimal :sum_duration, precision: 20, scale: 6, default: 0, null: false, comment: "Exact sum of folded durations in milliseconds"
      t.decimal :sum_square_duration, precision: 30, scale: 6, default: 0, null: false, comment: "Exact sum of squared durations, for pooled stddev"
      t.decimal :min_duration, precision: 15, scale: 6, comment: "Smallest folded duration in milliseconds"
      t.decimal :max_duration, precision: 15, scale: 6, comment: "Largest folded duration in milliseconds"
      t.text :histogram, comment: "JSON of DurationHistogram bucket index => count, for percentiles"

      t.timestamps
    end

    # upsert_all relies on MySQL resolving conflicts through any unique key,
    # so this must stay the table's only unique index besides the primary key.
    add_index :rails_pulse_rollups, [ :rollupable_type, :rollupable_id, :period_start, :writer_id ],
      unique: true,
      name: "idx_pulse_rollups_unique"
    add_index :rails_pulse_rollups, :period_start, name: "index_rails_pulse_rollups_on_period_start"
  end
end
