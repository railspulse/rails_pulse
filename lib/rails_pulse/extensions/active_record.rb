# frozen_string_literal: true

module RailsPulse
  module Extensions
    module ActiveRecord
      # Extends ActiveRecord::Relation with database-agnostic date grouping
      # This is a replacement for Groupdate that works regardless of ActiveRecord.default_timezone
      module QueryMethods
        # Groups records by date extracted from a timestamp column
        # Works across PostgreSQL, MySQL, and SQLite
        #
        # @param column [Symbol, String] the timestamp column to group by (default: :period_start)
        # @return [ActiveRecord::Relation] relation with DATE grouping applied
        #
        # @example Group summaries by date
        #   RailsPulse::Summary.where(...).group_by_date(:period_start).sum(:count)
        #   # => { Date(2024-01-01) => 100, Date(2024-01-02) => 150, ... }
        #
        # @example Group by different column
        #   Model.group_by_date(:created_at).count
        #
        def group_by_date(column = :period_start)
          group(Arel.sql(date_sql(column.to_s))).extending(DateResultTransformer)
        end

        # Groups records by hour extracted from a timestamp column
        # Works across PostgreSQL, MySQL, and SQLite
        #
        # @param column [Symbol, String] the timestamp column to group by (default: :period_start)
        # @return [ActiveRecord::Relation] relation with hour grouping applied
        #
        # @example Group summaries by hour
        #   RailsPulse::Summary.where(...).group_by_hour(:period_start).sum(:count)
        #   # => { Time(2024-01-01 14:00:00) => 100, Time(2024-01-01 15:00:00) => 150, ... }
        #
        def group_by_hour(column = :period_start)
          group(Arel.sql(hour_sql(column.to_s))).extending(HourResultTransformer)
        end

        private

        # Returns database-specific SQL for extracting date from timestamp
        def date_sql(column)
          "DATE(#{column})"
        end

        # Returns database-specific SQL for extracting datetime truncated to hour
        def hour_sql(column)
          case connection.adapter_name.downcase
          when "mysql", "mysql2"
            "DATE_FORMAT(#{column}, '%Y-%m-%d %H:00:00')"
          when "sqlite"
            "STRFTIME('%Y-%m-%d %H:00:00', #{column})"
          else
            # PostgreSQL and unknown adapters
            "DATE_TRUNC('hour', #{column})"
          end
        end
      end

      # Shared base for transforming aggregation result hash keys.
      # Include this module and implement #parse_key to specialize.
      module ResultTransformer
        def sum(*args)
          super.transform_keys { |k| parse_key(k) }
        end

        def count(*args)
          result = super
          # count can return an integer or a hash depending on whether group is used
          result.is_a?(Hash) ? result.transform_keys { |k| parse_key(k) } : result
        end

        def average(*args)
          super.transform_keys { |k| parse_key(k) }
        end

        def maximum(*args)
          super.transform_keys { |k| parse_key(k) }
        end

        def minimum(*args)
          super.transform_keys { |k| parse_key(k) }
        end

        def pluck(*args)
          result = super
          result.is_a?(Hash) ? result.transform_keys { |k| parse_key(k) } : result
        end
      end

      # Module to transform aggregation result keys from strings to Date objects
      # This makes the API match Groupdate's behavior
      module DateResultTransformer
        include ResultTransformer

        private

        def parse_key(date_str)
          Date.parse(date_str.to_s)
        end
      end

      # Module to transform aggregation result keys from strings to Time objects
      # Used for hourly grouping
      module HourResultTransformer
        include ResultTransformer

        private

        def parse_key(time_str)
          return time_str if time_str.is_a?(Time)
          return nil if time_str.nil? || time_str.to_s.strip.empty?
          # Parse as UTC since STRFTIME returns UTC strings from the database
          # Keep in UTC to match the time range boundaries used in queries
          Time.find_zone("UTC").parse(time_str.to_s)
        end
      end
    end
  end
end

# Extend ActiveRecord::Relation with our date grouping methods
ActiveRecord::Relation.include(RailsPulse::Extensions::ActiveRecord::QueryMethods)
