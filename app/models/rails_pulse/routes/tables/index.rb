module RailsPulse
  module Routes
    module Tables
      class Index
        def initialize(ransack_query:, period_type: nil, start_time:, params:)
          @ransack_query = ransack_query
          @period_type = period_type
          @start_time = start_time
          @params = params
        end

        def to_table
          # Store original sorts for manual handling
          original_sorts = @ransack_query.sorts

          # Get the original params and remove sort parameters
          original_params = @params[:q] || {}
          clean_params = original_params.reject { |key, _| key.to_s.ends_with?("_s") || key.to_s == "s" }

          # Create a fresh query without sorts
          clean_query = Summary.ransack(clean_params)
          summaries = clean_query.result(distinct: false)
            .joins("INNER JOIN rails_pulse_routes ON rails_pulse_routes.id = rails_pulse_summaries.summarizable_id")
            .where(
              summarizable_type: "RailsPulse::Route",
              period_type: @period_type
            )

          summaries = summaries.where(summarizable_id: @route.id) if @route

          # Build the grouped query
          grouped_summaries = summaries
            .group(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_routes.id",
              "rails_pulse_routes.path",
              "rails_pulse_routes.method"
            )
            .select(
              "rails_pulse_summaries.summarizable_id",
              "rails_pulse_summaries.summarizable_type",
              "rails_pulse_routes.id as route_id, rails_pulse_routes.path, rails_pulse_routes.method as route_method",
              "AVG(rails_pulse_summaries.avg_duration) as avg_duration",
              "MAX(rails_pulse_summaries.max_duration) as max_duration",
              "SUM(rails_pulse_summaries.count) as count",
              "SUM(rails_pulse_summaries.error_count) as error_count",
              "SUM(rails_pulse_summaries.success_count) as success_count"
            )

          # Handle sorting - convert Ransack sorts to work with aggregated fields
          if original_sorts.present?
            order_clauses = original_sorts.map do |sort|
              case sort.name
              when "avg_duration"
                "AVG(rails_pulse_summaries.avg_duration) #{sort.dir}"
              when "max_duration"
                "MAX(rails_pulse_summaries.max_duration) #{sort.dir}"
              when "count"
                "SUM(rails_pulse_summaries.count) #{sort.dir}"
              when "error_count"
                "SUM(rails_pulse_summaries.error_count) #{sort.dir}"
              when "success_count"
                "SUM(rails_pulse_summaries.success_count) #{sort.dir}"
              when "path"
                "rails_pulse_routes.path #{sort.dir}"
              when "method"
                "rails_pulse_routes.method #{sort.dir}"
              else
                # Default fallback
                "AVG(rails_pulse_summaries.avg_duration) #{sort.dir}"
              end
            end
            grouped_summaries = grouped_summaries.order(order_clauses.join(", "))
          else
            # Default ordering when no sorts are specified
            grouped_summaries = grouped_summaries.order("AVG(rails_pulse_summaries.avg_duration) DESC")
          end

          grouped_summaries
        end
      end
    end
  end
end
