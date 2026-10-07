module RailsPulse
  module Cloud
    # Several summary rows of one hour folded into one item's metrics: the
    # unmatched paths under one prefix, the routes or queries past the
    # per-hour cap, or two stored routes that share a pattern. Counts, totals
    # and status counts add up exactly, as do min, max, the mean and the
    # standard deviation; percentiles are the count-weighted average of the
    # rows', as SummaryService does when it rolls hours up into a day.
    module CombinedMetrics
      PERCENTILES = %i[p50_duration p95_duration p99_duration].freeze
      COUNTS = %i[error_count success_count status_2xx status_3xx status_4xx status_5xx].freeze

      module_function

      # @param rows [Array<#[]>] summary rows, or hashes with the same keys
      # @return [Hash] the metric fields of a summary item
      def of(rows, counts: COUNTS)
        rows = rows.reject { |row| row[:count].to_i.zero? }
        count = rows.sum { |row| row[:count].to_i }
        return { count: 0 } if count.zero?

        weighted_mean_sum = rows.sum { |row| row[:count].to_i * row[:avg_duration].to_f }
        {
          count: count,
          avg_duration: weighted_mean_sum / count,
          min_duration: rows.filter_map { |row| row[:min_duration]&.to_f }.min,
          max_duration: rows.filter_map { |row| row[:max_duration]&.to_f }.max,
          total_duration: rows.sum { |row| row[:total_duration].to_f },
          **PERCENTILES.index_with { |column| weighted(rows, column) },
          stddev_duration: Statistics.pooled_stddev(
            count: count,
            within_sum: rows.sum { |row| (row[:count].to_i - 1) * (row[:stddev_duration].to_f**2) },
            weighted_mean_sum: weighted_mean_sum,
            weighted_square_sum: rows.sum { |row| row[:count].to_i * (row[:avg_duration].to_f**2) }
          ),
          **counts.index_with { |column| rows.sum { |row| row[column].to_i } }
        }
      end

      def weighted(rows, column)
        present = rows.reject { |row| row[column].nil? }
        weight = present.sum { |row| row[:count].to_i }
        return nil if weight.zero?

        present.sum { |row| row[column].to_f * row[:count].to_i } / weight
      end
    end
  end
end
