module RailsPulse
  module Dashboard
    module Concerns
      module TimeRangeHelper
        private

        def period_range
          [ @period.days.ago.beginning_of_day, Time.current ]
        end
      end
    end
  end
end
