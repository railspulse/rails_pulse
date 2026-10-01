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
      upper_index = [ rank.ceil, n - 1 ].min

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

    # Sample standard deviation of the union of several groups, from three
    # sums over the groups that a database can compute in one GROUP BY, so
    # the groups never have to be loaded. Exact: equal to calculate_stddev
    # over all the groups' values together. For groups i with count n_i,
    # mean m_i and sample standard deviation s_i (nil for a group of one):
    #
    #   within_sum          = sum of (n_i - 1) * s_i^2
    #   weighted_mean_sum   = sum of n_i * m_i
    #   weighted_square_sum = sum of n_i * m_i^2
    #
    # @param count [Integer] Total number of values across the groups
    # @return [Float, nil] The standard deviation or nil if fewer than two values
    #
    # @example Groups [10, 20, 30] (n 3, mean 20, s 10) and [100, 400] (n 2, mean 250, s 212.13)
    #   Statistics.pooled_stddev(count: 5, within_sum: 45_200, weighted_mean_sum: 560, weighted_square_sum: 126_200)
    #   # => 164.83 (approximately; calculate_stddev of [10, 20, 30, 100, 400])
    def self.pooled_stddev(count:, within_sum:, weighted_mean_sum:, weighted_square_sum:)
      return nil if count < 2

      mean = weighted_mean_sum.to_f / count
      # The between-group term, sum of n_i * (m_i - mean)^2, expanded so it
      # needs only the two sums. Clamped because that expansion can come out
      # a hair below zero in floating point when every value is equal.
      sum_of_squares = within_sum.to_f + [ weighted_square_sum.to_f - (count * mean * mean), 0 ].max
      Math.sqrt(sum_of_squares / (count - 1))
    end
  end
end
