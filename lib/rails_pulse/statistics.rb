module RailsPulse
  module Statistics
    # Calculates percentile using linear interpolation
    #
    # @param sorted_values [Array<Numeric>] Pre-sorted array of values
    # @param percentile [Float] Percentile to calculate (0.0 to 1.0, e.g., 0.95 for p95)
    # @return [Float, nil] The calculated percentile or nil if array is empty
    #
    # @example
    #   Statistics.calculate_percentile([100, 200, 300, 400, 500], 0.95)
    #   # => 480.0 (interpolated value between 400 and 500)
    def self.calculate_percentile(sorted_values, percentile)
      return nil if sorted_values.empty?

      n = sorted_values.length
      rank = percentile * (n - 1)
      lower_index = rank.floor
      upper_index = [rank.ceil, n - 1].min

      if lower_index == upper_index
        sorted_values[lower_index]
      else
        fraction = rank - lower_index
        lower_value = sorted_values[lower_index]
        upper_value = sorted_values[upper_index]
        lower_value + (fraction * (upper_value - lower_value))
      end
    end

    # Calculates standard deviation using sample standard deviation formula
    #
    # @param values [Array<Numeric>] Array of values
    # @param mean [Numeric] Pre-calculated mean of the values
    # @return [Float, nil] The standard deviation or nil if insufficient data
    #
    # @example
    #   Statistics.calculate_stddev([100, 200, 300, 400, 500], 300)
    #   # => 158.11 (approximately)
    def self.calculate_stddev(values, mean)
      return nil if values.empty? || values.size == 1

      sum_of_squares = values.sum { |v| (v - mean) ** 2 }
      Math.sqrt(sum_of_squares / (values.size - 1))
    end
  end
end
