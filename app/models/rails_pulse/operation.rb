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
    belongs_to :request, class_name: "RailsPulse::Request"
    belongs_to :query, class_name: "RailsPulse::Query", optional: true

    # Validations
    validates :request_id, presence: true
    validates :operation_type, presence: true, inclusion: { in: OPERATION_TYPES }
    validates :label, presence: true
    validates :occurred_at, presence: true
    validates :duration, presence: true, numericality: { greater_than_or_equal_to: 0 }

    # Scopes (optional, for convenience)
    scope :by_type, ->(type) { where(operation_type: type) }

    before_validation :associate_query

    def self.ransackable_attributes(auth_object = nil)
      %w[id occurred_at label duration start_time average_query_time_ms query_count operation_type]
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

    def associate_query
      return unless operation_type == "sql" && label.present?

      normalized = normalize_query_label(label)
      self.query = RailsPulse::Query.find_or_create_by(normalized_sql: normalized)
    end

    # Generalized method to normalize SQL queries
    def normalize_query_label(label)
      return if label.blank?

      # Replace numeric values (e.g., IDs) with placeholders
      normalized = label.gsub(/\b\d+\b/, "?")

      # Replace both single-quoted and double-quoted strings with placeholders
      normalized = normalized.gsub(/(["']).*?\1/, "?")

      # Replace floating-point numbers with placeholders
      normalized = normalized.gsub(/\b\d+\.\d+\b/, "?")

      # Handle IN clauses (e.g., IN (1, 2, 3))
      normalized = normalized.gsub(/\bIN\s*\([^)]*\)/i, "IN (?)")

      # Handle comparison operators (e.g., bar_id = ?, price > ?)
      normalized = normalized.gsub(/\b(=|>|<|>=|<=)\s*\d+\b/, "\1 ?")

      normalized.strip
    end
  end
end
