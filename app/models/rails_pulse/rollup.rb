module RailsPulse
  # One writer process's cumulative aggregate of the requests (per route) or
  # SQL operations (per query) that detail capture folded instead of
  # persisting during one hour. Decision 0022.
  #
  # Rows are written by replace-upsert: a writer incarnation owns the rows
  # carrying its writer_id and overwrites them with its running totals, so
  # flushing twice is harmless and two processes never contend. Readers sum
  # across writer_ids. Sums, counts, min and max are exact; only the duration
  # histogram (for percentiles) is approximate.
  class Rollup < RailsPulse::ApplicationRecord
    self.table_name = "rails_pulse_rollups"

    UNIQUE_INDEX = :idx_pulse_rollups_unique

    belongs_to :rollupable, polymorphic: true

    validates :period_start, :writer_id, presence: true

    scope :for_hour, ->(hour_start) { where(period_start: hour_start) }

    # MySQL has no explicit conflict target and resolves through any unique
    # key, which is why the model's unique index must stay the only one.
    def self.upsert_rows(rows)
      return if rows.empty?

      unique_by = connection.supports_insert_conflict_target? ? UNIQUE_INDEX : nil
      upsert_all(rows, unique_by: unique_by)
    end

    def self.ransackable_attributes(_auth_object = nil)
      []
    end

    def self.ransackable_associations(_auth_object = nil)
      []
    end

    # table_exists?, rescued — for an upgrader who hasn't migrated yet
    def self.table_available?
      table_exists?
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def histogram_counts
      DurationHistogram.load(histogram).counts
    end
  end
end
