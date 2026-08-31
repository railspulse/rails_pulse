module RailsPulse
  class Finding < RailsPulse::ApplicationRecord
    self.table_name = "rails_pulse_findings"

    KINDS = %w[performance_regression error_rate_regression].freeze
    SEVERITIES = %w[warning critical].freeze
    STATUSES = %w[open acknowledged resolved].freeze

    validates :fingerprint, presence: true, uniqueness: true
    validates :kind,     inclusion: { in: KINDS }
    validates :severity, inclusion: { in: SEVERITIES }
    validates :status,   inclusion: { in: STATUSES }
    validates :subject_type, :subject_id, :metric, presence: true
    validates :first_detected_at, :last_detected_at, presence: true

    scope :open,         -> { where(status: "open") }
    scope :acknowledged, -> { where(status: "acknowledged") }
    scope :resolved,     -> { where(status: "resolved") }
    scope :unresolved,   -> { where(status: %w[open acknowledged]) }
    scope :critical,     -> { where(severity: "critical") }
    scope :recent,       -> { order(last_detected_at: :desc) }

    # Identity is the thing being reported, not the run that reported it: the
    # same route regressing on the same metric is one finding that keeps being
    # seen, not a new row every detection run. This mirrors how ExceptionGroup
    # fingerprints a raise site rather than a raise.
    def self.fingerprint_for(kind:, subject_type:, subject_id:, metric:)
      Digest::SHA256.hexdigest("#{kind}:#{subject_type}:#{subject_id}:#{metric}")
    end

    def self.ransackable_attributes(auth_object = nil)
      %w[
        id kind metric severity status subject_type subject_id
        baseline_value current_value delta ratio
        first_detected_at last_detected_at resolved_at detection_count changed_at
      ]
    end

    def self.ransackable_associations(auth_object = nil)
      []
    end

    # The record this finding is about. Nil for the overall request rollup,
    # which has no row of its own, and nil if the subject has since been cleaned
    # up — callers must handle both.
    def subject
      return nil if overall_requests?

      @subject ||= subject_type.constantize.find_by(id: subject_id)
    end

    def overall_requests?
      subject_type == "RailsPulse::Request" && subject_id.to_i.zero?
    end

    def subject_label
      return "All requests" if overall_requests?

      record = subject
      return "#{subject_type.demodulize} ##{subject_id}" if record.nil?

      case subject_type
      when "RailsPulse::Route" then record.path
      when "RailsPulse::Query" then record.normalized_sql
      when "RailsPulse::Job"   then record.name
      end.presence || "#{subject_type.demodulize} ##{subject_id}"
    end

    def unit
      metric == "error_rate" ? "%" : "ms"
    end

    def percent_change
      return nil if ratio.nil?

      (ratio - 1) * 100
    end

    def resolved?
      status == "resolved"
    end

    # A change point is only meaningful if one could be located, and its
    # precision depends on whether hourly summaries still covered the window.
    def change_point_known?
      changed_at.present?
    end

    def hourly_change_point?
      change_point_granularity == "hour"
    end

    def to_s
      "#{subject_label}: #{format_value(baseline_value)} → #{format_value(current_value)}"
    end

    private

    def format_value(value)
      return "—" if value.nil?

      metric == "error_rate" ? "#{value.round(2)}%" : "#{value.round(0).to_i}ms"
    end
  end
end
