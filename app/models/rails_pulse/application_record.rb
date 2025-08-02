module RailsPulse
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    connects_to(**RailsPulse.connects_to) if RailsPulse.connects_to
  end
end
