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

        private

        # Returns database-specific SQL for extracting date from timestamp
        def date_sql(column)
          adapter = connection.adapter_name.downcase

          case adapter
          when "postgresql"
            "DATE(#{column})"
          when "mysql", "mysql2"
            "DATE(#{column})"
          when "sqlite"
            "DATE(#{column})"
          else
            # Fallback for unknown adapters
            "DATE(#{column})"
          end
        end
      end

      # Module to transform aggregation result keys from strings to Date objects
      # This makes the API match Groupdate's behavior
      module DateResultTransformer
        def sum(*args)
          super.transform_keys { |date_str| Date.parse(date_str.to_s) }
        end

        def count(*args)
          result = super
          # count can return an integer or a hash depending on whether group is used
          result.is_a?(Hash) ? result.transform_keys { |date_str| Date.parse(date_str.to_s) } : result
        end

        def average(*args)
          super.transform_keys { |date_str| Date.parse(date_str.to_s) }
        end

        def maximum(*args)
          super.transform_keys { |date_str| Date.parse(date_str.to_s) }
        end

        def minimum(*args)
          super.transform_keys { |date_str| Date.parse(date_str.to_s) }
        end

        def pluck(*args)
          result = super
          # If grouping, transform the keys
          result.is_a?(Hash) ? result.transform_keys { |date_str| Date.parse(date_str.to_s) } : result
        end
      end
    end
  end
end

# Extend ActiveRecord::Relation with our date grouping methods
ActiveRecord::Relation.include(RailsPulse::Extensions::ActiveRecord::QueryMethods)
