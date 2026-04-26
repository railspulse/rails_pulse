module RailsPulse
  class Deployment < RailsPulse::ApplicationRecord
    self.table_name = "rails_pulse_deployments"

    validates :revision,    presence: true
    validates :deployed_at, presence: true

    scope :for_range, ->(start_time, end_time) { where(deployed_at: start_time..end_time) }
    scope :recent,    -> { order(deployed_at: :desc) }

    def self.ransackable_attributes(auth_object = nil)
      %w[id revision deployed_at created_at]
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
      { timestamp: deployed_at.to_i * 1000, revision: revision, deployed_at: deployed_at.iso8601 }
    end
  end
end
