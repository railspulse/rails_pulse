module RailsPulse
  class Request < ApplicationRecord
    self.table_name = "rails_pulse_requests"

    # Associations
    belongs_to :route, class_name: "RailsPulse::Route"
    has_many :operations, class_name: "RailsPulse::Operation", foreign_key: "request_id", dependent: :destroy

    # Validations
    validates :route_id, presence: true
    validates :occurred_at, presence: true
    validates :duration, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :status, presence: true
    validates :is_error, inclusion: { in: [true, false] }
    validates :request_uuid, presence: true, uniqueness: true

    before_create :set_request_uuid

    def self.ransackable_attributes(auth_object = nil)
      %w[id route_id occurred_at duration status status_indicator route_path]
    end

    def self.ransackable_associations(auth_object = nil)
      %w[route]
    end

    ransacker :occurred_at, formatter: ->(val) { Time.at(val.to_i) } do |parent|
      parent.table[:occurred_at]
    end

    ransacker :route_path do |parent|
      Arel.sql("rails_pulse_routes.path")
    end

    ransacker :status_indicator do |parent|
      # Calculate status indicator based on request_thresholds
      slow = RailsPulse.configuration.request_thresholds[:slow]
      very_slow = RailsPulse.configuration.request_thresholds[:very_slow]
      critical = RailsPulse.configuration.request_thresholds[:critical]
      
      Arel.sql("
        CASE 
          WHEN rails_pulse_requests.duration < #{slow} THEN 0
          WHEN rails_pulse_requests.duration < #{very_slow} THEN 1
          WHEN rails_pulse_requests.duration < #{critical} THEN 2
          ELSE 3
        END
      ")
    end

    def to_s
      occurred_at.strftime("%Y-%m-%d %H:%M:%S")
    end

    private

    def set_request_uuid
      self.request_uuid = SecureRandom.uuid if request_uuid.blank?
    end
  end
end
