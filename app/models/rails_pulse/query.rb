module RailsPulse
  class Query < ApplicationRecord
    self.table_name = "rails_pulse_queries"

    # Associations
    has_many :operations, class_name: "RailsPulse::Operation", inverse_of: :query

    # Validations
    validates :normalized_sql, presence: true, uniqueness: true

    def self.ransackable_attributes(auth_object = nil)
      %w[id normalized_sql average_query_time_ms execution_count total_time_consumed performance_status occurred_at]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[operations]
    end

    ransacker :average_query_time_ms do
      Arel.sql("COALESCE(AVG(rails_pulse_operations.duration), 0)")
    end

    ransacker :execution_count do
      Arel.sql("COUNT(rails_pulse_operations.id)")
    end

    ransacker :total_time_consumed do
      Arel.sql("COALESCE(SUM(rails_pulse_operations.duration), 0)")
    end

    ransacker :performance_status do
      # Calculate status indicator based on query_thresholds
      slow = RailsPulse.configuration.query_thresholds[:slow]
      very_slow = RailsPulse.configuration.query_thresholds[:very_slow]
      critical = RailsPulse.configuration.query_thresholds[:critical]
      
      Arel.sql("
        CASE 
          WHEN COALESCE(AVG(rails_pulse_operations.duration), 0) < #{slow} THEN 0
          WHEN COALESCE(AVG(rails_pulse_operations.duration), 0) < #{very_slow} THEN 1
          WHEN COALESCE(AVG(rails_pulse_operations.duration), 0) < #{critical} THEN 2
          ELSE 3
        END
      ")
    end

    ransacker :occurred_at do
      Arel.sql("MAX(rails_pulse_operations.occurred_at)")
    end

    def to_s
      id
    end
  end
end
