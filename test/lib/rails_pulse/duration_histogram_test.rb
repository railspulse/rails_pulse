require "test_helper"

module RailsPulse
  class DurationHistogramTest < ActiveSupport::TestCase
    # Structure Tests

    test "index_for is zero at or below the lowest bound" do
      assert_equal 0, DurationHistogram.index_for(0)
      assert_equal 0, DurationHistogram.index_for(0.05)
      assert_equal 0, DurationHistogram.index_for(DurationHistogram::LOWEST)
    end

    test "index_for is monotonic in duration" do
      durations = [ 0.2, 1, 5, 50, 500, 5_000, 50_000 ]

      indexes = durations.map { |d| DurationHistogram.index_for(d) }

      assert_equal indexes.sort, indexes
      assert_equal indexes.uniq, indexes
    end

    test "index_for clamps past the highest bound" do
      assert_equal DurationHistogram::MAX_INDEX, DurationHistogram.index_for(DurationHistogram::HIGHEST * 100)
    end

    test "value_for lands inside the bucket that index_for picked" do
      [ 0.3, 1.0, 17.2, 480.0, 12_000.0 ].each do |duration|
        index = DurationHistogram.index_for(duration)
        value = DurationHistogram.value_for(index)

        lower = DurationHistogram::LOWEST * DurationHistogram::GROWTH**(index - 1)
        upper = DurationHistogram::LOWEST * DurationHistogram::GROWTH**index

        assert_operator value, :>, lower
        assert_operator value, :<=, upper
      end
    end

    test "dump and load round-trip the counts" do
      histogram = DurationHistogram.new
      histogram.record(12.5)
      histogram.record(12.5)
      histogram.record(900)

      reloaded = DurationHistogram.load(histogram.dump)

      assert_equal histogram.counts, reloaded.counts
      assert_equal 3, reloaded.total
    end

    test "load tolerates blank text" do
      assert_predicate DurationHistogram.load(nil), :empty?
      assert_predicate DurationHistogram.load(""), :empty?
    end

    test "merge! adds counts bucket by bucket" do
      histogram = DurationHistogram.new
      histogram.record(10)
      other = DurationHistogram.new
      other.record(10)
      other.record(2_000)

      histogram.merge!(other.counts)

      assert_equal 3, histogram.total
      assert_equal 2, histogram.counts[DurationHistogram.index_for(10)]
    end

    # Percentile Tests

    test "percentile with no bucket counts equals the exact calculation" do
      exact = [ 100.0, 200.0, 300.0, 400.0, 500.0 ]

      [ 0.5, 0.95, 0.99 ].each do |p|
        expected = Statistics.calculate_percentile(exact, p)
        actual = DurationHistogram.percentile(counts: {}, exact_sorted: exact, percentile: p)

        assert_in_delta expected, actual, 1e-9
      end
    end

    test "percentile returns nil when both sources are empty" do
      assert_nil DurationHistogram.percentile(counts: {}, exact_sorted: [], percentile: 0.95)
    end

    test "percentile over buckets alone matches the exact calculation on the expanded multiset" do
      histogram = DurationHistogram.new
      durations = [ 5.0 ] * 30 + [ 50.0 ] * 10 + [ 500.0 ] * 5
      durations.each { |d| histogram.record(d) }
      expanded = durations.map { |d| DurationHistogram.value_for(DurationHistogram.index_for(d)) }.sort

      [ 0.5, 0.9, 0.95, 0.99 ].each do |p|
        expected = Statistics.calculate_percentile(expanded, p)
        actual = DurationHistogram.percentile(counts: histogram.counts, exact_sorted: [], percentile: p)

        assert_in_delta expected, actual, 1e-9
      end
    end

    test "percentile merges bucket counts with exact values in order" do
      histogram = DurationHistogram.new
      40.times { histogram.record(10.0) }
      exact = [ 1_000.0, 2_000.0, 4_000.0, 8_000.0 ]

      # 44 values, p95 rank 40.85 falls among the exact slow tail
      p95 = DurationHistogram.percentile(counts: histogram.counts, exact_sorted: exact, percentile: 0.95)

      assert_operator p95, :>=, 1_000.0
      assert_operator p95, :<=, 4_000.0
    end

    test "percentile stays within the bucket error bound for a mixed distribution" do
      rng = Random.new(42)
      durations = Array.new(2_000) { Math.exp(rng.rand * 8) }.sort # ~1ms .. ~3s
      histogram = DurationHistogram.new
      durations.each { |d| histogram.record(d) }
      tolerance = Math.sqrt(DurationHistogram::GROWTH) - 1

      [ 0.5, 0.95, 0.99 ].each do |p|
        exact = Statistics.calculate_percentile(durations, p)
        approximate = DurationHistogram.percentile(counts: histogram.counts, exact_sorted: [], percentile: p)

        assert_in_delta exact, approximate, exact * tolerance
      end
    end

    test "percentiles above the exact tail are near-exact when slow values are kept" do
      rng = Random.new(7)
      fast = Array.new(950) { rng.rand * 400.0 }
      slow = Array.new(50) { 500.0 + rng.rand * 5_000.0 }.sort
      histogram = DurationHistogram.new
      fast.each { |d| histogram.record(d) }

      all = (fast + slow).sort
      exact_p99 = Statistics.calculate_percentile(all, 0.99)
      approximate_p99 = DurationHistogram.percentile(counts: histogram.counts, exact_sorted: slow, percentile: 0.99)

      assert_in_delta exact_p99, approximate_p99, 1e-9
    end

    # Edge Cases

    test "percentile handles a single bucketed value" do
      histogram = DurationHistogram.new
      histogram.record(42.0)

      result = DurationHistogram.percentile(counts: histogram.counts, exact_sorted: [], percentile: 0.99)

      bucket_value = DurationHistogram.value_for(DurationHistogram.index_for(42.0))

      assert_in_delta bucket_value, result, 1e-9
    end

    test "normalize_counts drops non-positive entries and coerces string keys" do
      counts = DurationHistogram.normalize_counts({ "3" => "2", "7" => 0, 9 => -1 })

      assert_equal({ 3 => 2 }, counts)
    end
  end
end
