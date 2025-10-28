module RailsPulse
  class Route < RailsPulse::ApplicationRecord
    include Taggable

    self.table_name = "rails_pulse_routes"

    # Associations
    has_many :requests, class_name: "RailsPulse::Request", foreign_key: "route_id", dependent: :restrict_with_exception
    has_many :summaries, as: :summarizable, class_name: "RailsPulse::Summary", dependent: :destroy

    # Validations
    validates :method, presence: true
    validates :path, presence: true, uniqueness: { scope: :method, message: "and method combination must be unique" }

    # Scopes (optional, for convenience)
    scope :by_method_and_path, ->(method, path) { where(method: method, path: path).first_or_create }

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
      # Use a simpler database-agnostic approach - this is mainly used for sorting/filtering
      # so exact precision isn't as critical as avoiding database-specific functions
      Arel.sql("COUNT(rails_pulse_requests.id)")
    end

    def to_breadcrumb
      path
    end

    def self.average_response_time
      joins(:requests).average("rails_pulse_requests.duration") || 0
    end

    def path_and_method
      "#{path} #{method}"
    end
  end
end
