module RailsPulse
  class RouteControllerActionBackfiller
    def self.call
      new.call
    end

    def call
      results = { updated: 0, skipped: 0, already_set: 0, merged: 0 }
      RailsPulse::Route.find_each { |route| process_route(route, results) }
      consolidate_unrecognized_duplicates(results)
      results
    end

    private

    def process_route(route, results)
      # Skip rows already destroyed by an earlier merge in this run.
      return unless RailsPulse::Route.exists?(id: route.id)

      if route.controller_action.present?
        results[:already_set] += 1
        return
      end

      ca = recognized_controller_action(route) || controller_action_from_requests(route)

      if ca
        apply_controller_action(route, ca, results)
      else
        results[:skipped] += 1
      end
    end

    def recognized_controller_action(route)
      primary_method = route.http_methods_list.first
      return nil unless primary_method

      params = RailsPulse::RouteRecognizer.call(route.path, method: primary_method)
      params && [ params[:controller], params[:action] ].compact.join("#").presence
    end

    # Historical requests stored PascalCase class names (HomeController#index).
    # Normalize to the capture-time format (home#index).
    def controller_action_from_requests(route)
      raw = RailsPulse::Request.where(route_id: route.id)
        .where.not(controller_action: [ nil, "" ])
        .group(:controller_action)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(1)
        .pluck(:controller_action)
        .first

      normalize_controller_action(raw)
    end

    def normalize_controller_action(value)
      return nil if value.blank?

      controller, action = value.to_s.split("#", 2)
      return nil if controller.blank? || action.blank?

      "#{controller.delete_suffix("Controller").underscore}##{action}"
    end

    def apply_controller_action(route, ca, results)
      existing = RailsPulse::Route.find_by(controller_action: ca, path: route.path)
      if existing && existing.id != route.id
        RailsPulse::RouteMerger.call(target: existing, source: route)
        results[:merged] += 1
        return
      end

      route.update_column(:controller_action, ca)
      results[:updated] += 1
    rescue ActiveRecord::RecordNotUnique
      # Concurrent insert/update raced us; merge into the surviving row.
      existing = RailsPulse::Route.find_by!(controller_action: ca, path: route.path)
      RailsPulse::RouteMerger.call(target: existing, source: route) unless existing.id == route.id
      results[:merged] += 1
    end

    # Remaining null-action rows are unrecognized (404s). Group them by path so
    # GET+POST /unknown become one route before the null-action unique index is added.
    def consolidate_unrecognized_duplicates(results)
      paths = RailsPulse::Route.where(controller_action: nil)
        .group(:path)
        .having("COUNT(*) > 1")
        .pluck(:path)

      paths.each do |path|
        routes = RailsPulse::Route.where(controller_action: nil, path: path).order(:id).to_a
        winner = routes.shift
        next unless winner

        routes.each do |loser|
          next unless RailsPulse::Route.exists?(id: loser.id)

          RailsPulse::RouteMerger.call(target: winner, source: loser)
          results[:merged] += 1
        end
      end
    end
  end
end
