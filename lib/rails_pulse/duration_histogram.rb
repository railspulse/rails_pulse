require "json"

module RailsPulse
  # Counts request durations in buckets instead of keeping each value, so
  # percentiles can still be computed after the individual requests have
  # been discarded.
  #
  # Rather than storing 10,000 durations, it stores how many fell into each
  # of a fixed set of millisecond ranges — a few hundred counters at most,
  # however much traffic the hour saw. The ranges are narrow for fast
  # durations and wide for slow ones, so the accuracy of a value read back
  # stays proportional (within about 5%) whether it was 5ms or 5 seconds.
  #
  # Only the shape of the distribution is approximated. Callers keep sums,
  # counts, minima and maxima exactly alongside the histogram, and
  # `percentile` can mix the bucketed counts with exactly-kept durations —
  # so a percentile that lands among the kept values is exact, and one that
  # lands inside a bucket is off by at most that bucket's width.
  class DurationHistogram
    GROWTH = 1.1
    LOWEST = 0.1          # ms
    HIGHEST = 120_000.0   # ms
    LOG_GROWTH = Math.log(GROWTH)
    MAX_INDEX = (Math.log(HIGHEST / LOWEST) / LOG_GROWTH).ceil

    class << self
      # Bucket 0 holds everything at or below LOWEST; bucket i (i >= 1)
      # covers (LOWEST * GROWTH**(i-1), LOWEST * GROWTH**i], and the top
      # bucket absorbs everything past HIGHEST.
      def index_for(duration_ms)
        return 0 if duration_ms <= LOWEST

        [ (Math.log(duration_ms / LOWEST) / LOG_GROWTH).ceil, MAX_INDEX ].min
      end

      # The value a bucket's members are read back as: the geometric midpoint
      # of its bounds, so the value is off by at most sqrt(GROWTH) - 1
      # (about 4.9%) relative to the original.
      def value_for(index)
        return LOWEST if index.zero?

        LOWEST * GROWTH**(index - 0.5)
      end

      def load(json_text)
        counts = json_text.present? ? JSON.parse(json_text) : {}
        new(counts)
      end

      # Percentile (0.0..1.0) of the multiset formed by `counts` (bucket
      # index => occurrences) and `exact_sorted` (pre-sorted exact durations,
      # each counting once). Nil when both are empty.
      #
      # Interpolates with the same rank = p * (n - 1) rule as
      # Statistics.calculate_percentile, so with no bucketed counts it
      # returns exactly what calculate_percentile would.
      def percentile(counts:, exact_sorted:, percentile:)
        counts = normalize_counts(counts)
        return Statistics.calculate_percentile(exact_sorted, percentile) if counts.empty?

        total = exact_sorted.size + counts.each_value.sum
        rank = percentile * (total - 1)
        lower_index = rank.floor
        upper_index = [ rank.ceil, total - 1 ].min

        values = values_at_positions(counts, exact_sorted, [ lower_index, upper_index ])
        lower_value = values.fetch(lower_index)
        upper_value = values.fetch(upper_index)
        return lower_value if lower_index == upper_index

        fraction = rank - lower_index
        lower_value + (fraction * (upper_value - lower_value))
      end

      def normalize_counts(counts)
        (counts || {}).each_with_object({}) do |(index, n), result|
          n = n.to_i
          result[index.to_i] = n if n.positive?
        end
      end

      private

      # Values at the given 0-based positions of the ascending multiset, found
      # by merge-walking bucket runs and exact values without expanding them.
      def values_at_positions(counts, exact_sorted, positions)
        bucket_runs = counts.sort.map { |index, n| [ value_for(index), n ] }
        wanted = positions.uniq.sort
        found = {}
        cumulative = 0
        bucket_i = 0
        exact_i = 0
        wanted_i = 0

        while wanted_i < wanted.size
          bucket_value, bucket_count = bucket_runs[bucket_i]
          exact_value = exact_sorted[exact_i]

          if bucket_value && (exact_value.nil? || bucket_value <= exact_value)
            run_value, run_count = bucket_value, bucket_count
            bucket_i += 1
          elsif exact_value
            run_value, run_count = exact_value, 1
            exact_i += 1
          else
            break
          end

          while wanted_i < wanted.size && wanted[wanted_i] < cumulative + run_count
            found[wanted[wanted_i]] = run_value
            wanted_i += 1
          end
          cumulative += run_count
        end

        found
      end
    end

    def initialize(counts = {})
      @counts = self.class.normalize_counts(counts)
    end

    attr_reader :counts

    def record(duration_ms)
      index = self.class.index_for(duration_ms.to_f)
      @counts[index] = @counts.fetch(index, 0) + 1
    end

    def merge!(other_counts)
      self.class.normalize_counts(other_counts).each do |index, n|
        @counts[index] = @counts.fetch(index, 0) + n
      end
      self
    end

    def total
      @counts.each_value.sum
    end

    def empty?
      @counts.empty?
    end

    def dump
      JSON.generate(@counts)
    end
  end
end
