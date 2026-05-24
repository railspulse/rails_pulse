module RailsPulse
  class Deployment < RailsPulse::ApplicationRecord
    self.table_name = "rails_pulse_deployments"

    validates :revision,   presence: true
    validates :started_at, presence: true

    scope :for_range, ->(start_time, end_time) { where(started_at: start_time..end_time) }
    scope :recent,    -> { order(started_at: :desc) }

    def self.ransackable_attributes(auth_object = nil)
      %w[id revision started_at finished_at created_at]
    end

    def self.ransackable_associations(auth_object = nil)
      []
    end

    def metadata_hash
      return {} if metadata.blank?
      JSON.parse(metadata)
    rescue JSON::ParserError
      {}
    end

    def to_chart_marker
      { timestamp: started_at.to_i * 1000, revision: revision, started_at: started_at.iso8601 }
    end
  end
end
