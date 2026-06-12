module RailsPulse
  class Route < RailsPulse::ApplicationRecord
    include Taggable

    self.table_name = "rails_pulse_routes"

    # Associations
    has_many :requests, class_name: "RailsPulse::Request", foreign_key: "route_id", dependent: :restrict_with_exception
    has_many :summaries, as: :summarizable, class_name: "RailsPulse::Summary", dependent: :destroy

    # Validations
    validates :path, presence: true
    validates :http_methods, presence: true

    # Find an existing route by controller_action + path, or create one.
    # When a route already exists, the incoming http_method is appended to its
    # http_methods array if not already present (self-healing for PATCH/PUT etc.).
    # For requests without a controller_action (404s, middleware short-circuits),
    # falls back to grouping by path alone.
    def self.find_or_create_for_request(http_method, path, controller_action: nil)
      if controller_action.present?
        route = find_by(controller_action: controller_action, path: path)
        if route
          route.add_http_method(http_method)
          return route
        end

        # Use INSERT ... ON CONFLICT DO NOTHING rather than create_or_find_by so that
        # concurrent inserts for the same route are silently skipped at the database level.
        insert(
          { http_methods: [ http_method ].to_json, path: path, controller_action: controller_action,
            tags: "[]", created_at: Time.current, updated_at: Time.current }
        )
        find_by!(controller_action: controller_action, path: path)
      else
        route = find_by(controller_action: nil, path: path)
        if route
          route.add_http_method(http_method)
          return route
        end

        insert(
          { http_methods: [ http_method ].to_json, path: path, controller_action: nil,
            tags: "[]", created_at: Time.current, updated_at: Time.current }
        )
        where(controller_action: nil, path: path).order(:id).first!
      end
    end

    def http_methods_list
      return [] if http_methods.blank?
      JSON.parse(http_methods)
    rescue JSON::ParserError
      []
    end

    def add_http_method(http_method)
      return if http_method.blank?
      current = http_methods_list
      return if current.include?(http_method)
      update_column(:http_methods, (current + [ http_method ]).sort.to_json)
    end

    def self.ransackable_attributes(auth_object = nil)
      %w[path average_response_time_ms max_response_time_ms request_count requests_per_minute occurred_at requests_occurred_at error_count error_rate_percentage status_indicator]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[requests]
    end

    ransacker :average_response_time_ms do
      Arel.sql("COALESCE(AVG(rails_pulse_requests.duration), 0)")
    end

    ransacker :request_count do
      Arel.sql("COUNT(rails_pulse_requests.id)")
    end

    ransacker :occurred_at do |parent|
      parent.table[:occurred_at]
    end

    ransacker :requests_occurred_at do |_parent|
      Arel.sql("rails_pulse_requests.occurred_at")
    end

    ransacker :error_count do
      Arel.sql(
        "COALESCE(SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END), 0)"
      )
    end

    ransacker :max_response_time_ms do
      Arel.sql("COALESCE(MAX(rails_pulse_requests.duration), 0)")
    end

    ransacker :error_rate_percentage do
      Arel.sql("CASE WHEN COUNT(rails_pulse_requests.id) > 0 THEN ROUND((COALESCE(SUM(CASE WHEN rails_pulse_requests.is_error = true THEN 1 ELSE 0 END), 0) * 100.0) / COUNT(rails_pulse_requests.id), 2) ELSE 0 END")
    end

    ransacker :requests_per_minute do
      Arel.sql("COUNT(rails_pulse_requests.id)")
    end

    def to_breadcrumb
      "#{http_methods_list.sort.join('|')} #{path}".truncate(60)
    end

    def self.average_response_time
      joins(:requests).average("rails_pulse_requests.duration") || 0
    end

    def path_and_method
      "#{path} #{http_methods_list.join('|')}"
    end
  end
end
