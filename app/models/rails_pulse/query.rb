module RailsPulse
  class Query < RailsPulse::ApplicationRecord
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
      # Calculate status indicator based on query_thresholds with safe defaults
      config = RailsPulse.configuration rescue nil
      thresholds = config&.query_thresholds || { slow: 200, very_slow: 500, critical: 1000 }

      slow = (thresholds[:slow] || 200).to_f
      very_slow = (thresholds[:very_slow] || 500).to_f
      critical = (thresholds[:critical] || 1000).to_f

      # Use Arel to safely construct the SQL with parameterized values
      avg_duration = Arel.sql("COALESCE(AVG(rails_pulse_operations.duration), 0)")

      Arel::Nodes::Case.new(avg_duration)
        .when(avg_duration.lt(slow)).then(0)
        .when(avg_duration.lt(very_slow)).then(1)
        .when(avg_duration.lt(critical)).then(2)
        .else(3)
    end

    ransacker :occurred_at do
      Arel.sql("MAX(rails_pulse_operations.occurred_at)")
    end

    def to_s
      id
    end
  end
end
