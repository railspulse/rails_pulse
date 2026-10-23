# Base class providing common utilities for all query analyzers.
# Handles database adapter detection, SQL parsing, and normalization.
module RailsPulse
  module Analysis
    class BaseAnalyzer
      RECENT_OPERATIONS_WINDOW = 48.hours

      attr_reader :query, :operations

      def initialize(query, operations = [])
        @query = query
        @operations = Array(operations)
      end

      # Each analyzer must implement this method
      def analyze
        raise NotImplementedError, "#{self.class} must implement #analyze"
      end

      protected

      def sql
        @sql ||= query.normalized_sql
      end

      def recent_operations
        @recent_operations ||= operations.select { |op| op.occurred_at > RECENT_OPERATIONS_WINDOW.ago }
      end

      # "postgresql", "mysql" or "sqlite" for any adapter built on one of them
      # (PostGIS, Trilogy, ...), otherwise the adapter's own name in lowercase.
      def database_adapter
        @database_adapter ||= begin
          connection = RailsPulse::ApplicationRecord.connection
          (RailsPulse::DatabaseAdapter.family(connection) || connection.adapter_name.downcase).to_s
        end
      end

      def postgresql?
        database_adapter == "postgresql"
      end

      def mysql?
        database_adapter.in?([ "mysql", "mysql2" ])
      end

      def sqlite?
        database_adapter == "sqlite"
      end

      # Common SQL parsing utilities
      def extract_main_table(sql_string = sql)
        match = sql_string.match(/FROM\s+["'`]?(\w+)["'`]?/i)
        match ? match[1] : nil
      end

      def extract_where_clause(sql_string = sql)
        match = sql_string.match(/WHERE\s+(.+?)(?:\s+ORDER\s+BY|\s+GROUP\s+BY|\s+LIMIT|\s*$)/i)
        match ? match[1] : nil
      end

      def normalize_sql_for_pattern_detection(sql_string)
        return "" unless sql_string.present?

        sql_string.gsub(/\d+/, "?")              # Replace numbers with placeholders
                  .gsub(/'[^']*'/, "?")          # Replace strings with placeholders
                  .gsub(/\s+/, " ")              # Normalize whitespace
                  .strip
                  .downcase
      end
    end
  end
end
