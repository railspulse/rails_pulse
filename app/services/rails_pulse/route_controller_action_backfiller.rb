module RailsPulse
  class RouteControllerActionBackfiller
    def self.call
      new.call
    end

    def call
      results = { updated: 0, skipped: 0, already_set: 0 }
      RailsPulse::Route.find_each { |route| process_route(route, results) }
      results
    end

    private

    def process_route(route, results)
      if route.controller_action.present?
        results[:already_set] += 1
        return
      end

      primary_method = route.http_methods_list.first
      unless primary_method
        results[:skipped] += 1
        return
      end

      params = Rails.application.routes.recognize_path(
        route.path,
        method: primary_method.downcase.to_sym
      )
      ca = [ params[:controller], params[:action] ].compact.join("#").presence

      if ca
        route.update_column(:controller_action, ca)
        results[:updated] += 1
      else
        results[:skipped] += 1
      end
    rescue ActionController::RoutingError
      results[:skipped] += 1
    end
  end
end
