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

    # Smart normalization: preserve table/column names, replace only literal values
    def normalize_query_label(label)
      return nil if label.nil?
      return "" if label.empty?

      normalized = label.dup

      # Step 1: Temporarily protect quoted identifiers (backticks and double quotes that look like identifiers)
      protected_identifiers = {}
      identifier_counter = 0
      
      # Protect backticked identifiers (MySQL style)
      normalized = normalized.gsub(/`([^`]+)`/) do |match|
        placeholder = "__IDENTIFIER_#{identifier_counter}__"
        protected_identifiers[placeholder] = match
        identifier_counter += 1
        placeholder
      end
      
      # Protect double-quoted identifiers (PostgreSQL/SQL standard style)
      # Only protect if they appear in contexts where identifiers are expected
      normalized = normalized.gsub(/"([^"]+)"/) do |match|
        content = $1
        # Only protect if it looks like an identifier (no spaces, not a sentence)
        if content.match?(/^[a-zA-Z_][a-zA-Z0-9_]*$/) || content.include?('.')
          placeholder = "__IDENTIFIER_#{identifier_counter}__"
          protected_identifiers[placeholder] = match
          identifier_counter += 1
          placeholder
        else
          match  # Leave it as-is for now, will be replaced as string literal
        end
      end

      # Step 2: Replace literal values
      # Replace floating-point numbers first
      normalized = normalized.gsub(/(?<![a-zA-Z_])\b\d+\.\d+\b(?![a-zA-Z_])/, "?")
      
      # Replace integer literals
      normalized = normalized.gsub(/(?<![a-zA-Z_])\b\d+\b(?![a-zA-Z_])/, "?")
      
      # Replace string literals (single quotes)
      normalized = normalized.gsub(/'(?:[^']|'')*'/, "?")
      
      # Replace double-quoted string literals (not protected identifiers)
      normalized = normalized.gsub(/"(?:[^"]|"")*"/, "?")
      
      # Handle boolean literals
      normalized = normalized.gsub(/\b(true|false)\b/i, "?")

      # Step 3: Handle special SQL constructs
      # Handle IN clauses
      normalized = normalized.gsub(/\bIN\s*\(\s*([^)]+)\)/i) do |match|
        content = $1
        # Count commas to determine number of values
        value_count = content.split(',').length
        placeholders = Array.new(value_count, "?").join(", ")
        "IN (#{placeholders})"
      end
      
      # Handle BETWEEN clauses
      normalized = normalized.gsub(/\bBETWEEN\s+\?\s+AND\s+\?/i, "BETWEEN ? AND ?")

      # Step 4: Restore protected identifiers
      protected_identifiers.each do |placeholder, original|
        normalized = normalized.gsub(placeholder, original)
      end

      # Step 5: Clean up and normalize whitespace
      normalized = normalized.gsub(/\s+/, " ")

      normalized.strip
    end
  end
end
