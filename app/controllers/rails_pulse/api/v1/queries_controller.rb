module RailsPulse
  module Api
    module V1
      class QueriesController < BaseController
        SORT_COLUMNS = %w[total_duration avg_duration executions max_duration].freeze

        def index
          parsed_range = time_range
          return unless parsed_range
          since_start, until_end = parsed_range

          sort = params[:sort].presence
          if sort && !SORT_COLUMNS.include?(sort)
            return render json: { error: "Invalid sort. Valid values: #{SORT_COLUMNS.join(', ')}" }, status: :bad_request
          end

          # A route filter is answered from operations, which only the stats
          # path reads, so it implies a window the same way a sort does.
          if since_start || until_end || sort || params[:route].present?
            since_start ||= 24.hours.ago if until_end.nil?
            render_with_stats(since_start..until_end, sort || "total_duration")
          else
            data, meta = paginated(queries_scope.order(:id))
            render json: { data: data.map { |query| QuerySerializer.serialize(query) }, meta: meta }
          end
        end

        private

        # `hashed_sql` is the key Rails Pulse Cloud holds for a query, so an
        # exact match on it is how a caller gets from Cloud back to the SQL.
        def queries_scope
          scope = RailsPulse::Query.all
          scope = scope.where(hashed_sql: params[:hashed_sql]) if params[:hashed_sql].present?
          scope
        end

        def render_with_stats(range, sort)
          base = RailsPulse::Operation.where.not(query_id: nil).where(occurred_at: range)
          base = apply_route_filter(base)
          base = base.where(query_id: queries_scope.select(:id)) if params[:hashed_sql].present?
          total = base.distinct.count(:query_id)

          rows = base
            .group(:query_id)
            # Qualified: the route filter joins requests, which has its own
            # duration column.
            .select(
              "rails_pulse_operations.query_id, COUNT(*) AS executions, " \
              "AVG(rails_pulse_operations.duration) AS avg_duration, " \
              "MAX(rails_pulse_operations.duration) AS max_duration, " \
              "SUM(rails_pulse_operations.duration) AS total_duration, " \
              "MAX(rails_pulse_operations.repetition_count) AS max_repetition_count"
            )
            # query_id breaks ties so offset pages neither repeat nor skip rows.
            .order(Arel.sql("#{sort} DESC, rails_pulse_operations.query_id ASC"))
            .limit(limit)
            .offset(offset)
            .to_a

          queries = RailsPulse::Query.where(id: rows.map(&:query_id)).index_by(&:id)
          locations = source_locations(base, rows.map(&:query_id))
          data = rows.filter_map do |row|
            query = queries[row.query_id]
            QuerySerializer.serialize(query, stats: stats_for(row, locations[row.query_id])) if query
          end

          render json: { data: data, meta: { total: total, limit: limit, offset: offset } }
        end

        # Restricts the operations to those issued while serving one route, so
        # "what is slow inside this endpoint" is one call rather than a guess.
        # A bare integer is a route id; anything else matches the controller
        # action or path the way the routes endpoint's search does.
        def apply_route_filter(scope)
          route = params[:route].to_s
          return scope if route.blank?

          scope = scope.joins(request: :route)
          return scope.where(rails_pulse_routes: { id: route.to_i }) if route.match?(/\A\d+\z/)

          term = RailsPulse::LikePattern.containing(route.downcase)
          scope.where(
            "LOWER(rails_pulse_routes.controller_action) LIKE :term #{RailsPulse::LikePattern::CLAUSE} " \
            "OR LOWER(rails_pulse_routes.path) LIKE :term #{RailsPulse::LikePattern::CLAUSE}",
            term: term
          )
        end

        # Where each query was issued from, most frequent first. Without this a
        # caller knows a query is slow but not which line of code runs it.
        # Counted over the same operations as the stats, so with a route filter
        # a query shared across the app names the call sites in that endpoint.
        def source_locations(operations, query_ids, per_query: 3)
          return {} if query_ids.empty?

          counts = operations
            .where(query_id: query_ids)
            .where.not(codebase_location: nil)
            .group("rails_pulse_operations.query_id", "rails_pulse_operations.codebase_location")
            .count

          counts.group_by { |(query_id, _), _| query_id }.transform_values do |entries|
            entries.sort_by { |(_, location), count| [ -count, location ] }
              .first(per_query)
              .map { |(_, location), count| { location: location, count: count } }
          end
        end

        def stats_for(row, locations)
          {
            executions:           row.executions.to_i,
            avg_duration_ms:      row.avg_duration.to_f.round(1),
            max_duration_ms:      row.max_duration.to_f.round(1),
            total_duration_ms:    row.total_duration.to_f.round(1),
            max_repetition_count: row.max_repetition_count&.to_i,
            source_locations:     locations || []
          }
        end
      end
    end
  end
end
