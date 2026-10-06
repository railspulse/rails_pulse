module RailsPulse
  # A resolved start/end range plus the bucketing helpers charts and cards
  # need: day count, calendar dates/hour-starts inside it, and the
  # equal-length prior window for comparisons.
  class TimeWindow
    attr_reader :start_time, :end_time

    # nil (not raised) when either bound is missing — callers already have
    # a "no range selected" fallback to use instead.
    def self.build(start_time, end_time)
      return nil if start_time.nil? || end_time.nil?

      new(start_time, end_time)
    end

    def initialize(start_time, end_time)
      @start_time = coerce(start_time)
      @end_time = coerce(end_time)
    end

    # Whole days spanned, rounded rather than truncated (a range a few
    # seconds short of N days still counts as N). Always at least 1.
    def days
      [ ((end_time - start_time) / 1.day).round, 1 ].max
    end

    # Every full calendar day inside the window, ascending. Skips a leading
    # day whose midnight falls before the window start.
    def dates
      first_date = start_time.beginning_of_day == start_time ? start_time.to_date : (start_time.to_date + 1)
      return [] if first_date > end_time.to_date

      (first_date..end_time.to_date).to_a
    end

    # Every hour-start inside the window, ascending.
    def hour_starts
      starts = []
      current = start_time.beginning_of_hour
      current += 1.hour if current < start_time
      while current <= end_time
        starts << current
        current += 1.hour
      end
      starts
    end

    # The start of each chart bucket from the window's start, as epoch
    # seconds: one calendar day or one hour apart in Time.zone. A day is 23
    # or 25 hours across a daylight-saving change, so stepping a fixed 86,400
    # seconds would drift off local midnight and miss every summary after it.
    def bucket_timestamps(period_type)
      step = period_type.to_s == "hour" ? 1.hour : 1.day
      stamps = []
      current = start_time
      while current <= end_time
        stamps << current.to_i
        current += step
      end
      stamps
    end

    # The window of the same length immediately preceding this one, for
    # period-over-period comparisons. `unit` is "day" or "hour".
    def previous(unit)
      span = unit == "hour" ? (end_time - start_time) : days.days
      self.class.new(start_time - span, start_time)
    end

    private

    def coerce(value)
      value.is_a?(Numeric) ? Time.zone.at(value) : value.in_time_zone
    end
  end
end
