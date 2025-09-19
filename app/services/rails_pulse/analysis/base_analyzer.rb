# Base class providing common utilities for all query analyzers.
# Handles database adapter detection, SQL parsing, and normalization.
module RailsPulse
  module Analysis
    class BaseAnalyzer
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
        @recent_operations ||= operations.select { |op| op.occurred_at > 48.hours.ago }
      end

      # Utility method for database adapter detection
      def database_adapter
        @database_adapter ||= RailsPulse::ApplicationRecord.connection.adapter_name.downcase
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
        match = sql_string.match(/FROM\s+(\w+)/i)
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
