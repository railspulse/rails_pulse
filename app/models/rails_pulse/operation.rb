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

    ransacker :occurred_at, formatter: ->(val) {
      # Handle different time formats for database compatibility
      case val
      when Time, DateTime, ActiveSupport::TimeWithZone
        val.utc.iso8601
      when String
        Time.zone.parse(val).utc.iso8601
      when Integer
        Time.at(val).utc.iso8601
      else
        # Fallback: try to parse as integer timestamp
        Time.at(val.to_i).utc.iso8601
      end
    } do |parent|
      parent.table[:occurred_at]
    end

    def to_s
      id
    end

    private

    def has_request_or_job_run
      return if request_id.present? || job_run_id.present?

      errors.add(:base, "Operation must belong to a request or a job run")
    end

    def associate_query
      return unless operation_type == "sql" && label.present?

      normalized = normalize_query_label(label)
      self.query = RailsPulse::Query.find_or_create_by(normalized_sql: normalized)
    end

    # Normalize SQL query using the dedicated service
    def normalize_query_label(label)
      RailsPulse::SqlQueryNormalizer.normalize(label)
    end
  end
end
