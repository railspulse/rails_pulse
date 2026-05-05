module RailsPulse
  class Host < RailsPulse::ApplicationRecord
    self.table_name = "rails_pulse_hosts"

    has_many :routes, class_name: "RailsPulse::Route", foreign_key: "host_id", dependent: :restrict_with_exception

    validates :name, presence: true, uniqueness: true

    def to_s
      name
    end
  end
end
