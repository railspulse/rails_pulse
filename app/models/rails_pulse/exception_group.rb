module RailsPulse
  class ExceptionGroup < RailsPulse::ApplicationRecord
    self.table_name = "rails_pulse_exception_groups"

    STATUSES = %w[open resolved ignored].freeze

    has_many :occurrences, class_name: "RailsPulse::ExceptionOccurrence",
             foreign_key: :exception_group_id, dependent: :destroy

    validates :fingerprint, presence: true
    validates :exception_class, presence: true
    validates :first_seen_at, :last_seen_at, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :recent,       -> { order(last_seen_at: :desc) }
    scope :by_class,     ->(klass) { where(exception_class: klass) }
    scope :open,         -> { where(status: "open") }
    scope :resolved,     -> { where(status: "resolved") }
    scope :preservable,  -> { where(preserve: false) }

    def self.ransackable_attributes(auth_object = nil)
      %w[id exception_class fingerprint first_seen_at last_seen_at occurrence_count status resolved_at preserve]
    end
  end
end
