require "test_helper"

module RailsPulse
  module Charts
    class OperationsChartTest < ActiveSupport::TestCase
      fixtures :rails_pulse_operations, :rails_pulse_requests, :rails_pulse_routes, :rails_pulse_queries

      # Helper: build a plain Ruby object with the fields OperationsChart reads
      Op = Struct.new(:operation_type, :start_time, :duration)

      def make_op(type:, start_time:, duration:)
        Op.new(type, start_time.to_f, duration.to_f)
      end

      # Structure Tests

      test "OperationBar struct has operation, duration, left_pct, width_pct, and depth fields" do
        bar = OperationsChart::OperationBar.new(nil, 10.0, 5.0, 20.0, 1)

        assert_nil bar.operation
        assert_in_delta(10.0, bar.duration)
        assert_in_delta(5.0, bar.left_pct)
        assert_in_delta(20.0, bar.width_pct)
        assert_equal 1,    bar.depth
      end

      test "LANE_DISPLAY covers all known operation types" do
        expected_types = %w[controller template layout partial collection sql cache_read cache_write http job mailer storage]

        expected_types.each do |type|
          assert OperationsChart::LANE_DISPLAY.key?(type), "LANE_DISPLAY missing entry for '#{type}'"
        end
      end

      test "exposes bars, min_start, max_end, total_duration, max_depth, and lane_labels" do
        chart = OperationsChart.new([])

        assert_respond_to chart, :bars
        assert_respond_to chart, :min_start
        assert_respond_to chart, :max_end
        assert_respond_to chart, :total_duration
        assert_respond_to chart, :max_depth
        assert_respond_to chart, :lane_labels
      end

      # Edge Cases

      test "handles empty operations collection" do
        chart = OperationsChart.new([])

        assert_empty chart.bars
        assert_equal 0,   chart.min_start
        assert_equal 1,   chart.max_end
        assert_equal 1,   chart.total_duration
        assert_equal 0,   chart.max_depth
        assert_empty chart.lane_labels
      end

      test "handles single operation" do
        op    = make_op(type: "sql", start_time: 0, duration: 50)
        chart = OperationsChart.new([ op ])

        assert_equal 1,  chart.bars.length
        assert_equal 0,  chart.max_depth
        assert_equal 50, chart.total_duration
      end

      test "total_duration defaults to 1 when all durations are zero" do
        op    = make_op(type: "controller", start_time: 0, duration: 0)
        chart = OperationsChart.new([ op ])

        assert_equal 1, chart.total_duration
      end

      test "total_duration is at least 1 when negative operation durations make max_end less than min_start" do
        # If every operation has a large negative duration, max_end < min_start and
        # total_duration is negative — dividing by it inverts left_pct for bars with
        # higher start_times, producing negative CSS percentages.
        ops = [
          make_op(type: "controller", start_time: 500,   duration: -600),
          make_op(type: "sql",        start_time: 1_000, duration: -900)
        ]
        chart = OperationsChart.new(ops)

        assert_operator chart.total_duration, :>=, 1
        chart.bars.each do |bar|
          assert_operator bar.left_pct,  :>=, 0, "left_pct was #{bar.left_pct}"
          assert_operator bar.width_pct, :>=, 0, "width_pct was #{bar.width_pct}"
        end
      end

      test "bar width_pct is non-negative when an individual operation has a negative duration" do
        # total_duration stays positive here (the controller op anchors it), but the
        # SQL bar's negative duration produces a negative width_pct without clamping.
        ops = [
          make_op(type: "controller", start_time: 0, duration: 100),
          make_op(type: "sql",        start_time: 0, duration: -50)
        ]
        chart = OperationsChart.new(ops)

        sql_bar = chart.bars.find { |b| b.operation.operation_type == "sql" }

        assert_operator sql_bar.width_pct, :>=, 0, "width_pct was #{sql_bar.width_pct}"
      end

      # Calculation Tests

      test "min_start equals smallest start_time" do
        ops = [
          make_op(type: "controller", start_time: 5,  duration: 20),
          make_op(type: "sql",        start_time: 10, duration: 5)
        ]
        chart = OperationsChart.new(ops)

        assert_in_delta(5.0, chart.min_start)
      end

      test "max_end equals largest start_time plus duration" do
        ops = [
          make_op(type: "controller", start_time: 0,  duration: 30),
          make_op(type: "sql",        start_time: 10, duration: 50)  # ends at 60
        ]
        chart = OperationsChart.new(ops)

        assert_in_delta(60.0, chart.max_end)
      end

      test "total_duration spans min_start to max_end" do
        ops = [
          make_op(type: "controller", start_time: 5,  duration: 20),  # ends at 25
          make_op(type: "sql",        start_time: 10, duration: 40)   # ends at 50
        ]
        chart = OperationsChart.new(ops)

        assert_in_delta(45.0, chart.total_duration)  # 50 - 5
      end

      test "duration on bar is rounded to whole milliseconds" do
        op    = make_op(type: "sql", start_time: 0, duration: 12.567)
        chart = OperationsChart.new([ op ])

        assert_equal 13, chart.bars.first.duration
      end

      test "first bar left_pct is near zero when operation starts at min_start" do
        ops = [
          make_op(type: "controller", start_time: 0, duration: 100),
          make_op(type: "sql",        start_time: 50, duration: 10)
        ]
        chart = OperationsChart.new(ops)

        first_bar = chart.bars.find { |b| b.operation.operation_type == "controller" }

        assert_operator first_bar.left_pct, :>=, 0
        assert_operator first_bar.left_pct, :<, 5
      end

      test "width_pct is proportional to duration relative to total_duration" do
        ops = [
          make_op(type: "controller", start_time: 0,  duration: 100),
          make_op(type: "sql",        start_time: 0,  duration: 50)
        ]
        chart = OperationsChart.new(ops)

        controller_bar = chart.bars.find { |b| b.operation.operation_type == "controller" }
        sql_bar        = chart.bars.find { |b| b.operation.operation_type == "sql" }

        assert_operator controller_bar.width_pct, :>, sql_bar.width_pct
        assert_in_delta controller_bar.width_pct, sql_bar.width_pct * 2, 2
      end

      test "bars are built for every operation passed in" do
        ops = [
          make_op(type: "controller", start_time: 0,  duration: 100),
          make_op(type: "template",   start_time: 10, duration: 40),
          make_op(type: "sql",        start_time: 20, duration: 5)
        ]
        chart = OperationsChart.new(ops)

        assert_equal 3, chart.bars.length
      end

      # Swim Lane / Depth Tests

      test "single operation type gets depth 0" do
        op    = make_op(type: "controller", start_time: 0, duration: 100)
        chart = OperationsChart.new([ op ])

        assert_equal 0, chart.bars.first.depth
      end

      test "controller gets depth 0 and sql gets depth 1 when both present" do
        ops = [
          make_op(type: "controller", start_time: 0,  duration: 100),
          make_op(type: "sql",        start_time: 10, duration: 5)
        ]
        chart = OperationsChart.new(ops)

        controller_bar = chart.bars.find { |b| b.operation.operation_type == "controller" }
        sql_bar        = chart.bars.find { |b| b.operation.operation_type == "sql" }

        assert_equal 0, controller_bar.depth
        assert_equal 1, sql_bar.depth
      end

      test "template and layout share the same depth" do
        ops = [
          make_op(type: "template", start_time: 0,  duration: 50),
          make_op(type: "layout",   start_time: 10, duration: 30)
        ]
        chart = OperationsChart.new(ops)

        template_bar = chart.bars.find { |b| b.operation.operation_type == "template" }
        layout_bar   = chart.bars.find { |b| b.operation.operation_type == "layout" }

        assert_equal template_bar.depth, layout_bar.depth
      end

      test "partial and collection share the same depth" do
        ops = [
          make_op(type: "partial",    start_time: 0,  duration: 20),
          make_op(type: "collection", start_time: 25, duration: 10)
        ]
        chart = OperationsChart.new(ops)

        partial_bar    = chart.bars.find { |b| b.operation.operation_type == "partial" }
        collection_bar = chart.bars.find { |b| b.operation.operation_type == "collection" }

        assert_equal partial_bar.depth, collection_bar.depth
      end

      test "depths are compacted when intermediate lane types are absent" do
        # Only controller (order 0) and sql (order 3) — no view/partial in between
        # Depths should be 0 and 1, not 0 and 3
        ops = [
          make_op(type: "controller", start_time: 0,  duration: 100),
          make_op(type: "sql",        start_time: 10, duration: 5)
        ]
        chart = OperationsChart.new(ops)

        depths = chart.bars.map(&:depth).uniq.sort

        assert_equal [ 0, 1 ], depths
      end

      test "unknown operation type falls back to depth 0" do
        op    = make_op(type: "unknown_custom", start_time: 0, duration: 10)
        chart = OperationsChart.new([ op ])

        assert_equal 0, chart.bars.first.depth
      end

      # max_depth Tests

      test "max_depth is 0 with only one lane type present" do
        ops = [
          make_op(type: "sql", start_time: 0, duration: 10),
          make_op(type: "sql", start_time: 20, duration: 10)
        ]
        chart = OperationsChart.new(ops)

        assert_equal 0, chart.max_depth
      end

      test "max_depth increases with each additional lane" do
        ops = [
          make_op(type: "controller", start_time: 0,  duration: 100),
          make_op(type: "template",   start_time: 5,  duration: 80),
          make_op(type: "sql",        start_time: 10, duration: 5)
        ]
        chart = OperationsChart.new(ops)

        # controller=0, template=1 (view), sql=2 (database) → max_depth=2
        assert_equal 2, chart.max_depth
      end

      # Lane Label Tests

      test "lane_labels returns depth-label pairs for present operation types" do
        ops = [
          make_op(type: "controller", start_time: 0,  duration: 100),
          make_op(type: "sql",        start_time: 10, duration: 5)
        ]
        chart = OperationsChart.new(ops)

        assert_equal [ [ 0, "Action" ], [ 1, "Database" ] ], chart.lane_labels
      end

      test "template and layout produce a single View label" do
        ops = [
          make_op(type: "template", start_time: 0,  duration: 50),
          make_op(type: "layout",   start_time: 10, duration: 30)
        ]
        chart = OperationsChart.new(ops)

        view_labels = chart.lane_labels.select { |_, label| label == "View" }

        assert_equal 1, view_labels.length
      end

      test "lane_labels are ordered from outermost to innermost layer" do
        ops = [
          make_op(type: "sql",        start_time: 0, duration: 5),
          make_op(type: "controller", start_time: 0, duration: 100),
          make_op(type: "template",   start_time: 5, duration: 80)
        ]
        chart = OperationsChart.new(ops)

        labels = chart.lane_labels.map { |_, label| label }

        assert_equal [ "Action", "View", "Database" ], labels
      end

      test "lane_labels is empty for empty operations" do
        chart = OperationsChart.new([])

        assert_empty chart.lane_labels
      end

      # Fixture-Based Integration Tests

      test "builds bars correctly from real fixture operations" do
        ops   = rails_pulse_operations(:sql_operation_1, :controller_operation_1, :sql_operation_3)
        chart = OperationsChart.new(ops)

        assert_equal 3, chart.bars.length
        chart.bars.each do |bar|
          assert_operator bar.left_pct,  :>=, 0
          assert_operator bar.width_pct, :>=, 0
          assert_operator bar.depth,     :>=, 0
        end
      end

      test "controller and sql fixture operations get correct swim lane depths" do
        ops   = rails_pulse_operations(:sql_operation_1, :controller_operation_1)
        chart = OperationsChart.new(ops)

        controller_bar = chart.bars.find { |b| b.operation.operation_type == "controller" }
        sql_bar        = chart.bars.find { |b| b.operation.operation_type == "sql" }

        assert_equal 0, controller_bar.depth
        assert_equal 1, sql_bar.depth
      end

      test "handles operations with all different lane types" do
        ops = [
          make_op(type: "controller", start_time: 0, duration: 100),
          make_op(type: "template", start_time: 5, duration: 80),
          make_op(type: "partial", start_time: 10, duration: 40),
          make_op(type: "sql", start_time: 15, duration: 5),
          make_op(type: "cache_read", start_time: 20, duration: 2),
          make_op(type: "http", start_time: 25, duration: 30)
        ]
        chart = OperationsChart.new(ops)

        # Should have 6 different depths (0-5)
        depths = chart.bars.map(&:depth).uniq.sort

        assert_operator depths.length, :>=, 5
        assert_equal 5, chart.max_depth
      end

      test "handles large collection of fixture operations efficiently" do
        # Load all operations from fixtures
        ops = RailsPulse::Operation.all.to_a

        chart = OperationsChart.new(ops)

        # Should handle any number of operations
        assert_equal ops.length, chart.bars.length
        assert_operator chart.max_depth, :>=, 0
        refute_empty chart.lane_labels if ops.any?
      end
    end
  end
end
