module RailsPulse
  class HostsController < ApplicationController
    def index
      @hosts = Host
        .left_joins(routes: :requests)
        .group("rails_pulse_hosts.id")
        .select(
          "rails_pulse_hosts.*",
          "COUNT(DISTINCT rails_pulse_routes.id) as routes_count",
          "COUNT(rails_pulse_requests.id) as requests_count",
          "AVG(rails_pulse_requests.duration) as avg_duration"
        )
        .order("requests_count DESC")
    end

    def show
      @host = Host.find(params[:id])
      @routes = @host.routes
        .left_joins(:requests)
        .group("rails_pulse_routes.id")
        .select(
          "rails_pulse_routes.*",
          "COUNT(rails_pulse_requests.id) as requests_count",
          "AVG(rails_pulse_requests.duration) as avg_duration",
          "SUM(CASE WHEN rails_pulse_requests.is_error THEN 1 ELSE 0 END) as error_count"
        )
        .order("requests_count DESC")
    end
  end
end
