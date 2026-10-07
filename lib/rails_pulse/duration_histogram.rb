require "json"

module RailsPulse
  # A fixed log-spaced histogram of durations in milliseconds, for computing
  # percentiles over requests whose exact durations were not kept.
  #
  # Bucket 0 holds everything at or below LOWEST; bucket i (i >= 1) covers
  # (LOWEST * GROWTH**(i-1), LOWEST * GROWTH**i], and the top bucket absorbs
  # everything past HIGHEST. A bucket stands in for its members at the
  # geometric midpoint of its bounds, so a value read back from the histogram
  # is off by at most sqrt(GROWTH) - 1 (about 4.9%) relative to the original.
  # Sums, minima and maxima are never derived from buckets — callers keep
  # those exactly — only the shape of the distribution is approximated.
  #
  # `percentile` interpolates over the multiset formed by the bucketed counts
  # together with individually-known exact durations, using the same
  # rank = p * (n - 1) rule as Statistics.calculate_percentile; with no
  # bucketed counts it returns exactly what calculate_percentile would.
  class DurationHistogram
    GROWTH = 1.1
    LOWEST = 0.1          # ms
    HIGHEST = 120_000.0   # ms
    LOG_GROWTH = Math.log(GROWTH)
    MAX_INDEX = (Math.log(HIGHEST / LOWEST) / LOG_GROWTH).ceil

    class << self
      def index_for(duration_ms)
        return 0 if duration_ms <= LOWEST

        [ (Math.log(duration_ms / LOWEST) / LOG_GROWTH).ceil, MAX_INDEX ].min
      end

      # The value a bucket's members are read back as.
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
