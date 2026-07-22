module RailsPulse
  class RouteControllerActionBackfiller
    def self.call
      new.call
    end

    def call
      results = { updated: 0, skipped: 0, already_set: 0, merged: 0 }
      RailsPulse::Route.find_each { |route| process_route(route, results) }
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

      primary_method = route.http_methods_list.first
      unless primary_method
        results[:skipped] += 1
        return
      end

      params = RailsPulse::RouteRecognizer.call(route.path, method: primary_method)
      ca = params && [ params[:controller], params[:action] ].compact.join("#").presence

      if ca
        apply_controller_action(route, ca, results)
      else
        results[:skipped] += 1
      end
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
  end
end
