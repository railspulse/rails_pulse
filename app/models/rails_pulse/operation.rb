require "digest"

module RailsPulse
  class Operation < RailsPulse::ApplicationRecord
    self.table_name = "rails_pulse_operations"

    OPERATION_TYPES = %w[
      sql
      controller
      template
      partial
      layout
      collection
      cache_read
      cache_write
      http
      job
      mailer
      storage
    ].freeze

    # Associations
    belongs_to :request, class_name: "RailsPulse::Request", optional: true
    belongs_to :job_run, class_name: "RailsPulse::JobRun", optional: true
    belongs_to :query, class_name: "RailsPulse::Query", optional: true

    # Validations
    validates :operation_type, presence: true, inclusion: { in: OPERATION_TYPES }
    validates :label, presence: true
    validates :occurred_at, presence: true
    validates :duration, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validate :has_request_or_job_run

    # Scopes (optional, for convenience)
    scope :by_type, ->(type) { where(operation_type: type) }

    before_validation :associate_query
    before_validation :truncate_label

    # Bulk-insert a batch of operation hashes captured during a request or job run.
    # `context` is merged into every row to bind it to its parent — either
    # `{ request_id: id }` or `{ job_run_id: id, request_id: nil }`.
    #
    # SQL operations are handled in two phases to minimise DB round-trips:
    #   1. Normalise each unique SQL source once and collect hashed→normalised pairs.
    #   2. Resolve (or create) the corresponding Query records in bulk rather than
    #      one create_or_find_by per operation, which matters for N+1-heavy requests.
    #
    # insert_all! is used instead of individual creates to bypass ActiveRecord
    # callbacks and validations — normalisation and truncation are done inline above.
    # All rows must have the same key set, so keys are union-normalised before insert.
    def self.persist_bulk(ops, context)
      return if ops.empty?

      # Phase 1: normalise each unique SQL source once.
      # norm_cache avoids re-normalising repeated SQL (e.g. N+1 queries).
      # norm_map feeds the bulk Query resolver: { hashed_sql => normalized_sql }.
      norm_cache = {}
      norm_map = {}
      ops.each do |op|
        next unless op[:operation_type] == "sql"
        sql_source = op[:actual_sql].presence || op[:label].presence
        next unless sql_source
        unless norm_cache.key?(sql_source)
          normalized = RailsPulse::SqlQueryNormalizer.normalize(sql_source)
          hashed = Digest::MD5.hexdigest(normalized)
          norm_cache[sql_source] = [ hashed, normalized ]
          norm_map[hashed] ||= normalized
        end
      end

      # Phase 2: resolve Query IDs in bulk (1 SELECT in steady state).
      query_id_map = RailsPulse::Query.bulk_find_or_create(norm_map)

      now = Time.current
      rows = ops.map do |op|
        op = op.merge(context).merge(created_at: now, updated_at: now)
        if op[:operation_type] == "sql"
          sql_source = op[:actual_sql].presence || op[:label].presence
          if sql_source && (meta = norm_cache[sql_source])
            hashed, normalized = meta
            op = op.merge(label: normalized.truncate(255), query_id: query_id_map[hashed])
          end
        end
        op[:label] = op[:label]&.truncate(255)
        # actual_sql is used for normalization above but should not be persisted
        # unless the user has opted in — it may contain unparameterized PII.
        op[:actual_sql] = nil unless RailsPulse.configuration.capture_actual_sql
        op
      end
      # insert_all! requires every row to have identical keys.
      # cache_hit defaults to false for non-cache operations so we don't send explicit nil
      # into a column that may carry a NOT NULL constraint from the add_diagnostic_fields migration.
      all_keys = rows.flat_map(&:keys).uniq
      rows = rows.map { |r| all_keys.each_with_object({}) { |k, h| h[k] = r.fetch(k) { k == :cache_hit ? false : nil } } }
      insert_all!(rows)
    end

    def self.ransackable_attributes(auth_object = nil)
      %w[id occurred_at label duration start_time average_query_time_ms query_count operation_type query_id]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[]
    end

    ransacker :average_query_time_ms do
      Arel.sql("COALESCE(AVG(rails_pulse_operations.duration), 0)")
    end

    ransacker :query_count do
      Arel.sql("COUNT(rails_pulse_operations.id)")
    end

    # Handle different time formats for database compatibility. An
    # unparseable value becomes nil, which Ransack treats as "no filter",
    # rather than a 500 from a hand-edited query string.
    OCCURRED_AT_FORMATTER = lambda do |val|
      case val
      when Time, DateTime, ActiveSupport::TimeWithZone
        val.utc.iso8601
      when String
        Time.zone.parse(val)&.utc&.iso8601
      when Integer
        Time.at(val).utc.iso8601
      else
        # Fallback: try to parse as integer timestamp
        Time.at(val.to_i).utc.iso8601
      end
    rescue ArgumentError, TypeError
      nil
    end

    ransacker :occurred_at, formatter: OCCURRED_AT_FORMATTER do |parent|
      parent.table[:occurred_at]
    end

    def to_breadcrumb
      label.to_s.truncate(60)
    end

    def to_s
      id
    end

    private

    def has_request_or_job_run
      return if request_id.present? || job_run_id.present?

      errors.add(:base, "Operation must belong to a request or a job run")
    end

    def truncate_label
      self.label = label&.truncate(255)
    end

    def associate_query
      return unless operation_type == "sql"

      # actual_sql is the canonical source; fall back to label for pre-migration records
      sql_source = actual_sql.presence || label.presence
      return unless sql_source

      normalized = RailsPulse::SqlQueryNormalizer.normalize(sql_source)
      hashed = Digest::MD5.hexdigest(normalized)

      unless self.query&.hashed_sql == hashed
        self.query = RailsPulse::Query.find_or_create_by(hashed_sql: hashed) do |q|
          q.normalized_sql = normalized
        end
      end
      self.label = normalized.truncate(255)
    end
  end
end
