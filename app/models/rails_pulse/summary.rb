module RailsPulse
  class Summary < ApplicationRecord
    self.table_name = "rails_pulse_summaries"

    PERIOD_TYPES = %w[hour day week month].freeze

    # Polymorphic association
    belongs_to :summarizable, polymorphic: true, optional: true  # Optional for Request summaries

    # Convenience associations for easier querying
    belongs_to :route, -> { where(rails_pulse_summaries: { summarizable_type: "RailsPulse::Route" }) },
               foreign_key: "summarizable_id", class_name: "RailsPulse::Route", optional: true
    belongs_to :query, -> { where(rails_pulse_summaries: { summarizable_type: "RailsPulse::Query" }) },
               foreign_key: "summarizable_id", class_name: "RailsPulse::Query", optional: true

    # Validations
    validates :period_type, inclusion: { in: PERIOD_TYPES }
    validates :period_start, presence: true
    validates :period_end, presence: true

    # Scopes
    scope :for_period_type, ->(type) { where(period_type: type) }
    scope :for_date_range, ->(start_date, end_date) {
      where(period_start: start_date..end_date)
    }
    scope :for_requests, -> { where(summarizable_type: "RailsPulse::Request") }
    scope :for_routes, -> { where(summarizable_type: "RailsPulse::Route") }
    scope :for_queries, -> { where(summarizable_type: "RailsPulse::Query") }
    scope :recent, -> { order(period_start: :desc) }

    # Special scope for overall request summaries
    scope :overall_requests, -> {
      where(summarizable_type: "RailsPulse::Request", summarizable_id: 0)
    }

    # Ransack configuration
    def self.ransackable_attributes(auth_object = nil)
      %w[
        period_start period_end avg_duration max_duration count error_count
        requests_per_minute error_rate_percentage route_path_cont
        execution_count total_time_consumed normalized_sql occurred_at
      ]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[route query]
    end

    # Custom ransackers for calculated fields (designed to work with GROUP BY queries)
    ransacker :count do
      Arel.sql("SUM(rails_pulse_summaries.count)")  # Use SUM for proper grouping
    end

    ransacker :requests_per_minute do
      Arel.sql("SUM(rails_pulse_summaries.count) / 60.0")  # Use SUM for consistency
    end

    ransacker :error_rate_percentage do
      Arel.sql("(SUM(rails_pulse_summaries.error_count) * 100.0) / SUM(rails_pulse_summaries.count)")  # Use SUM for both
    end

    # Ransacker for route path sorting (when joined with routes table)
    ransacker :route_path do
      Arel.sql("rails_pulse_routes.path")
    end

    # Ransacker for route path filtering using subquery (works without JOIN)
    ransacker :route_path_cont do |parent|
      Arel.sql(<<-SQL)
        rails_pulse_summaries.summarizable_id IN (
          SELECT id FROM rails_pulse_routes
          WHERE rails_pulse_routes.path LIKE '%' || ? || '%'
        )
      SQL
    end

    # Ransackers for queries table calculated fields
    ransacker :execution_count do
      Arel.sql("SUM(rails_pulse_summaries.count)")  # Total executions
    end

    ransacker :total_time_consumed do
      Arel.sql("SUM(rails_pulse_summaries.count * rails_pulse_summaries.avg_duration)")  # Total time consumed
    end

    # Ransacker for query SQL sorting (when joined with queries table)
    ransacker :normalized_sql do
      Arel.sql("rails_pulse_queries.normalized_sql")
    end

    # Ransacker for average duration in grouped queries (needed for queries table sorting)
    ransacker :avg_duration do
      Arel.sql("AVG(rails_pulse_summaries.avg_duration)")
    end

    class << self
      def calculate_period_end(period_type, start_time)
        case period_type
        when "hour"  then start_time.end_of_hour
        when "day"   then start_time.end_of_day
        when "week"  then start_time.end_of_week
        when "month" then start_time.end_of_month
        end
      end

      def normalize_period_start(period_type, time)
        case period_type
        when "hour"  then time.beginning_of_hour
        when "day"   then time.beginning_of_day
        when "week"  then time.beginning_of_week
        when "month" then time.beginning_of_month
        end
      end
    end
  end
end
