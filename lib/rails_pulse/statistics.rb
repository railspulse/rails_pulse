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

    # Mean of values weighted by their weights, skipping nil values and
    # zero weights. Used to combine per-period percentiles into a longer
    # period's estimate, weighted by each period's request count.
    #
    # @param pairs [Array<Array(Numeric, Numeric)>] [value, weight] pairs
    # @return [Float, nil] The weighted mean or nil if no pair has weight
    #
    # @example
    #   Statistics.weighted_mean([[100, 3], [500, 1]])
    #   # => 200.0
    def self.weighted_mean(pairs)
      pairs = pairs.reject { |value, weight| value.nil? || weight.to_f.zero? }
      total_weight = pairs.sum { |_, weight| weight }
      return nil if total_weight.zero?

      pairs.sum { |value, weight| value * weight }.to_f / total_weight
    end

    # Sample standard deviation of the union of several groups, from each
    # group's count, mean and sample standard deviation alone. Exact: equal
    # to calculate_stddev over all the groups' values together. A group of
    # one has no deviation of its own (nil) but still contributes its
    # distance from the combined mean.
    #
    # @param groups [Array<Array(Integer, Numeric, Numeric)>] [count, mean, stddev] per group
    # @return [Float, nil] The standard deviation or nil if fewer than two values in total
    #
    # @example
    #   Statistics.pooled_stddev([[3, 20.0, 10.0], [2, 250.0, 212.13]])
    #   # => 164.83 (approximately; calculate_stddev of [10, 20, 30, 100, 400])
    def self.pooled_stddev(groups)
      groups = groups.select { |count, _, _| count.to_i.positive? }
      count = groups.sum { |group_count, _, _| group_count }
      return nil if count < 2

      mean = groups.sum { |group_count, group_mean, _| group_count * group_mean.to_f } / count
      sum_of_squares = groups.sum do |group_count, group_mean, group_stddev|
        ((group_count - 1) * (group_stddev || 0) ** 2) + (group_count * (group_mean.to_f - mean) ** 2)
      end
      Math.sqrt(sum_of_squares / (count - 1))
    end
  end
end
