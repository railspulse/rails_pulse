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

    # Breadcrumbs fall back to #to_s without this, which renders the object's
    # inspect string. Revisions can be full 40-char SHAs, so truncate.
    def to_breadcrumb
      short_revision
    end

    def short_revision
      revision.to_s.length > 12 ? revision.to_s.first(12) : revision.to_s
    end

    def in_progress?
      finished_at.blank?
    end

    # Wall-clock seconds the deploy took, or nil while it is still running.
    def duration
      return nil if in_progress? || started_at.blank?
      finished_at - started_at
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
