module RailsPulse
  module Api
    module V1
      class RoutesController < BaseController
        SORT_COLUMNS = %w[request_count avg_duration error_count].freeze

        def index
          parsed_range = time_range
          return unless parsed_range
          since_start, until_end = parsed_range

          sort = params[:sort].presence
          if sort && !SORT_COLUMNS.include?(sort)
            return render json: { error: "Invalid sort. Valid values: #{SORT_COLUMNS.join(', ')}" }, status: :bad_request
          end

          scope = RailsPulse::Route.all
          # Exact matches, unlike `search`: a route is identified by its path
          # and controller action together, and a substring would also return
          # `/orders/:id/items` for `/orders/:id`.
          scope = scope.where(path: params[:path]) if params[:path].present?
          scope = scope.where(controller_action: params[:controller_action]) if params[:controller_action].present?
          if params[:search].present?
            term = RailsPulse::LikePattern.containing(params[:search].downcase)
            scope = scope.where(
              "LOWER(path) LIKE :term #{RailsPulse::LikePattern::CLAUSE} " \
              "OR LOWER(controller_action) LIKE :term #{RailsPulse::LikePattern::CLAUSE}",
              term: term
            )
          end

          if since_start || until_end || sort
            since_start ||= 24.hours.ago if until_end.nil?
            render_with_stats(scope, since_start..until_end, sort || "request_count")
          else
            data, meta = paginated(scope.order(:path, :id))
            render json: { data: data.map { |route| RouteSerializer.serialize(route) }, meta: meta }
          end
        end

        private

        def render_with_stats(scope, range, sort)
          base = RailsPulse::Request.where(occurred_at: range)
          base = base.where(route_id: scope.select(:id)) if %i[search path controller_action].any? { |name| params[name].present? }

          # HAVING rather than a filter over the fetched page: a route busy
          # enough to qualify can rank below the limit, and dropping it after
          # the fact returns nothing while an answer exists.
          grouped = base.group(:route_id)
          grouped = grouped.having("COUNT(*) >= ?", min_requests) if min_requests > 1

          # Grouping yields one row per route, so counting the rows counts the
          # routes that qualify.
          routes_with_traffic = base.distinct.count(:route_id)
          total = min_requests > 1 ? grouped.count.size : routes_with_traffic

          # CASE WHEN on the boolean column itself is valid on SQLite, PostgreSQL
          # and MySQL alike, so no adapter-specific literal is interpolated.
          rows = grouped
            .select(
              "route_id, COUNT(*) AS request_count, AVG(duration) AS avg_duration, " \
              "SUM(CASE WHEN is_error THEN 1 ELSE 0 END) AS error_count"
            )
            # route_id breaks ties so offset pages neither repeat nor skip rows.
            .order(Arel.sql("#{sort} DESC, route_id ASC"))
            .limit(limit)
            .offset(offset)
            .to_a

          routes = RailsPulse::Route.where(id: rows.map(&:route_id)).index_by(&:id)
          data = rows.filter_map do |row|
            route = routes[row.route_id]
            RouteSerializer.serialize(route, stats: stats_for(row)) if route
          end

          meta = { total: total, limit: limit, offset: offset }
          # Lets a caller tell "nothing ran in this window" from "nothing ran
          # often enough", which are different next steps, without asking again
          # at a lower threshold.
          if min_requests > 1
            meta[:min_requests] = min_requests
            meta[:routes_with_traffic] = routes_with_traffic
          end

          render json: { data: data, meta: meta }
        end

        def min_requests
          integer_param(:min_requests, 1, 1..MAX_INTEGER)
        end

        def stats_for(row)
          {
            request_count:   row.request_count.to_i,
            avg_duration_ms: row.avg_duration.to_f.round(1),
            error_count:     row.error_count.to_i
          }
        end
      end
    end
  end
end
