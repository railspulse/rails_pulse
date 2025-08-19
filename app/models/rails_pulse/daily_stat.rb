module RailsPulse
  class DailyStat < RailsPulse::ApplicationRecord
    self.table_name = "rails_pulse_daily_stats"

    # Validations
    validates :date, presence: true
    validates :entity_type, presence: true, inclusion: { in: %w[route request query] }
    validates :entity_id, presence: true, unless: -> { entity_type == "request" }
    validates :total_requests, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :avg_duration, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :max_duration, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :error_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :p95_duration, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    # Unique constraint  
    validates :entity_id, uniqueness: { scope: [ :date, :entity_type ] }, allow_nil: true
    validates :date, uniqueness: { scope: :entity_type }, if: -> { entity_type == "request" && entity_id.nil? }

    # JSON field for hourly data
    # Format: {"0": {"requests": 45, "avg_duration": 234, "errors": 2}, "1": {...}, ...}
    # Note: No serialize needed - Rails 8 + SQLite handles JSON columns automatically

    # Scopes
    scope :for_entity, ->(entity_type, entity_id = nil) do
      query = where(entity_type: entity_type)
      query = query.where(entity_id: entity_id) if entity_id
      query
    end

    scope :for_date_range, ->(start_date, end_date) do
      where(date: start_date..end_date)
    end

    scope :routes, -> { where(entity_type: "route") }
    scope :requests, -> { where(entity_type: "request") }
    scope :queries, -> { where(entity_type: "query") }

    # Helper methods
    def hourly_breakdown_for(hour)
      return {} unless hourly_data.is_a?(Hash)
      hourly_data[hour.to_s] || {}
    end

    def has_hourly_data?
      hourly_data.present? && hourly_data.is_a?(Hash)
    end

    def completed_hours
      return [] unless has_hourly_data?
      hourly_data.keys.map(&:to_i).sort
    end

    def self.for_route(route_id)
      for_entity("route", route_id)
    end

    def self.upsert_hourly_data(date:, entity_type:, entity_id:, hour:, data:)
      record = find_or_initialize_by(
        date: date,
        entity_type: entity_type,
        entity_id: entity_id
      )

      # Initialize hourly_data if needed
      record.hourly_data ||= {}

      # Add this hour's data
      record.hourly_data[hour.to_s] = data

      # Initialize other fields if this is a new record
      if record.new_record?
        record.total_requests = 0
        record.error_count = 0
      end

      record.save!
      record
    end

    def self.finalize_daily_aggregates(date:, entity_type:, entity_id:, aggregates:)
      record = find_by(
        date: date,
        entity_type: entity_type,
        entity_id: entity_id
      )

      return nil unless record

      record.update!(aggregates)
      record
    end
  end
end
