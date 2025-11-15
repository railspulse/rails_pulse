module RailsPulse
  class Summary < RailsPulse::ApplicationRecord
    self.table_name = "rails_pulse_summaries"

    PERIOD_TYPES = %w[hour day week month].freeze

    # Polymorphic association
    belongs_to :summarizable, polymorphic: true, optional: true  # Optional for Request summaries

    # Convenience associations for easier querying
    belongs_to :route, -> { where(rails_pulse_summaries: { summarizable_type: "RailsPulse::Route" }) },
               foreign_key: "summarizable_id", class_name: "RailsPulse::Route", optional: true
    belongs_to :query, -> { where(rails_pulse_summaries: { summarizable_type: "RailsPulse::Query" }) },
               foreign_key: "summarizable_id", class_name: "RailsPulse::Query", optional: true
    belongs_to :job,
               -> { where(rails_pulse_summaries: { summarizable_type: "RailsPulse::Job" }) },
               foreign_key: "summarizable_id", class_name: "RailsPulse::Job", optional: true

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
    scope :for_jobs, -> { where(summarizable_type: "RailsPulse::Job") }
    scope :by_job_name, ->(job_name) { for_jobs.joins(:job).where(rails_pulse_jobs: { name: job_name }) }
    scope :recent, -> { order(period_start: :desc) }

    # Special scope for overall request summaries
    scope :overall_requests, -> {
      where(summarizable_type: "RailsPulse::Request", summarizable_id: 0)
    }

    # Tag filtering scope for charts and metrics
    # Filters summaries based on disabled tags in the underlying route/query
    scope :with_tag_filters, ->(disabled_tags = [], show_non_tagged = true) {
      # Separate "non_tagged" from actual tags (it's a virtual tag)
      actual_disabled_tags = disabled_tags.reject { |tag| tag == "non_tagged" }

      # Return early if no filters are applied
      return all if actual_disabled_tags.empty? && show_non_tagged

      # Determine which table to join based on summarizable_type
      # We need to handle both Route and Query summaries
      relation = all

      # Filter route summaries
      route_ids = RailsPulse::Route.all

      # Exclude routes with disabled tags
      actual_disabled_tags.each do |tag|
        route_ids = route_ids.where.not("tags LIKE ?", "%#{tag}%")
      end

      # Exclude non-tagged routes if show_non_tagged is false
      route_ids = route_ids.where("tags IS NOT NULL AND tags != '[]'") unless show_non_tagged

      route_ids = route_ids.pluck(:id)

      # Filter query summaries
      query_ids = RailsPulse::Query.all

      # Exclude queries with disabled tags
      actual_disabled_tags.each do |tag|
        query_ids = query_ids.where.not("tags LIKE ?", "%#{tag}%")
      end

      # Exclude non-tagged queries if show_non_tagged is false
      query_ids = query_ids.where("tags IS NOT NULL AND tags != '[]'") unless show_non_tagged

      query_ids = query_ids.pluck(:id)

      # Apply filters: include only summaries for filtered routes/queries
      # If no routes/queries match the filter, we need to ensure nothing is returned
      # Use -1 as an impossible ID instead of 0 (which might be used for aggregates)
      relation = relation.where(
        "(" \
        "  (summarizable_type = 'RailsPulse::Route' AND summarizable_id IN (?)) OR " \
        "  (summarizable_type = 'RailsPulse::Query' AND summarizable_id IN (?)) OR " \
        "  (summarizable_type = 'RailsPulse::Request')" \
        ")",
        route_ids.presence || [ -1 ],
        query_ids.presence || [ -1 ]
      )

      relation
    }

    # Ransack configuration
    def self.ransackable_attributes(auth_object = nil)
      %w[
        period_start period_end avg_duration min_duration max_duration count error_count
        requests_per_minute error_rate_percentage route_path_cont
        execution_count total_time_consumed normalized_sql
        summarizable_id summarizable_type
      ]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[route query job]
    end

    # Note: Basic fields like count, avg_duration, min_duration, max_duration
    # are handled automatically by Ransack using actual database columns

    # Custom ransackers for calculated fields only
    ransacker :requests_per_minute do
      Arel.sql("rails_pulse_summaries.count / 60.0")
    end

    ransacker :error_rate_percentage do
      Arel.sql("(rails_pulse_summaries.error_count * 100.0) / rails_pulse_summaries.count")
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

    # Sorting-specific ransackers for GROUP BY compatibility (used only in ORDER BY)
    # These use different names to avoid conflicts with filtering
    ransacker :avg_duration_sort do
      Arel.sql("AVG(rails_pulse_summaries.avg_duration)")
    end

    ransacker :max_duration_sort do
      Arel.sql("MAX(rails_pulse_summaries.max_duration)")
    end

    ransacker :count_sort do
      Arel.sql("SUM(rails_pulse_summaries.count)")
    end

    ransacker :error_count_sort do
      Arel.sql("SUM(rails_pulse_summaries.error_count)")
    end

    ransacker :success_count_sort do
      Arel.sql("SUM(rails_pulse_summaries.success_count)")
    end

    ransacker :total_time_consumed_sort do
      Arel.sql("SUM(rails_pulse_summaries.count * rails_pulse_summaries.avg_duration)")
    end

    # Alias execution_count_sort to count_sort for queries table compatibility
    ransacker :execution_count_sort do
      Arel.sql("SUM(rails_pulse_summaries.count)")
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
