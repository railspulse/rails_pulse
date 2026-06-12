module RailsPulse
  class RouteMigrator
    def self.call
      new.call
    end

    def call
      results = { merged: 0, skipped: 0, unchanged: 0 }
      RailsPulse::Route.find_each { |route| process_route(route, results) }
      results
    end

    private

    def process_route(route, results)
      primary_method = route.http_methods_list.first
      return results[:skipped] += 1 unless primary_method

      params = Rails.application.routes.recognize_path(
        route.path,
        method: primary_method.downcase.to_sym
      )
      normalized = RailsPulse::RoutePathNormalizer.normalize(route.path, params)

      # Derive controller_action from the recognized route params if not already stored.
      recognized_ca = [ params[:controller], params[:action] ].compact.join("#").presence

      if normalized == route.path
        route.update_column(:controller_action, recognized_ca) if route.controller_action.nil? && recognized_ca.present?
        results[:unchanged] += 1
        return
      end

      ca_for_target = recognized_ca || route.controller_action
      target = RailsPulse::Route.find_by(controller_action: ca_for_target, path: normalized)

      if target
        route.http_methods_list.each { |m| target.add_http_method(m) }
      else
        target = RailsPulse::Route.create!(
          http_methods: route.http_methods,
          path: normalized,
          controller_action: ca_for_target,
          tags: route.tags || "[]"
        )
      end

      ActiveRecord::Base.transaction do
        route.requests.update_all(route_id: target.id)
        route.destroy!
      end

      results[:merged] += 1
    rescue ActionController::RoutingError
      results[:skipped] += 1
    end
  end
end
