module RailsPulse
  module Charts
    # Lays out a request's or job run's operations as swim-lane bars for the
    # trace and the operations table.
    #
    # An N+1 can record thousands of identical operations, and rendering one
    # bar and one table row for each produces megabytes of HTML. Consecutive
    # operations in the same lane with the same type and label, separated by
    # less than MERGE_GAP_RATIO of the trace, collapse into one bar that spans
    # them, carries their combined duration and links to the slowest of them.
    # When more than MAX_BARS bars remain, only the slowest MAX_BARS are kept.
    class OperationsChart
      OperationBar = Struct.new(:operation, :duration, :left_pct, :width_pct, :depth, :count, :total_duration) do
        def repeated?
          count.to_i > 1
        end
      end

      LANE_DISPLAY = {
        "controller"  => { label: "Action",   order: 0 },
        "template"    => { label: "View",      order: 1 },
        "layout"      => { label: "View",      order: 1 },
        "partial"     => { label: "Partial",   order: 2 },
        "collection"  => { label: "Partial",   order: 2 },
        "sql"         => { label: "Database",  order: 3 },
        "cache_read"  => { label: "Cache",     order: 4 },
        "cache_write" => { label: "Cache",     order: 4 },
        "http"        => { label: "External",  order: 5 },
        "job"         => { label: "External",  order: 5 },
        "mailer"      => { label: "External",  order: 5 },
        "storage"     => { label: "External",  order: 5 }
      }.freeze

      MAX_BARS = 250
      MERGE_GAP_RATIO = 0.005
      PCT_PRECISION = 3

      attr_reader :bars, :min_start, :max_end, :total_duration, :max_depth, :lane_labels,
                  :operations_count, :hidden_operations_count, :hidden_bars_count

      HORIZONTAL_OFFSET_PX = 20

      Group = Struct.new(:operations, :start, :finish, :depth)

      def initialize(operations)
        @operations = operations.to_a
        @operations_count = @operations.size
        @min_start = @operations.map { |op| op.start_time.to_f }.min || 0
        @max_end = @operations.map { |op| op.start_time.to_f + op.duration.to_f }.max || 1
        @total_duration = [ @max_end - @min_start, 0 ].max.nonzero? || 1
        @bars = build_bars
        @max_depth = @bars.map(&:depth).max || 0
        @lane_labels = build_lane_labels
      end

      def truncated?
        hidden_bars_count.positive?
      end

      private

      def build_bars
        bars = build_groups.map { |group| bar_for(group) }

        kept = bars.size > MAX_BARS ? bars.max_by(MAX_BARS, &:total_duration) : bars
        @hidden_bars_count = bars.size - kept.size
        @hidden_operations_count = @operations_count - kept.sum(&:count)

        kept.sort_by.with_index { |bar, index| [ bar.left_pct, index ] }
      end

      def build_groups
        depth_map = build_depth_map
        merge_gap = @total_duration * MERGE_GAP_RATIO
        open_by_depth = {}
        groups = []

        @operations.each_with_index.sort_by { |op, index| [ op.start_time.to_f, index ] }.each do |op, _|
          depth = depth_map[op.operation_type]
          start = op.start_time.to_f
          finish = start + op.duration.to_f
          open = open_by_depth[depth]

          if open && same_kind?(open.operations.first, op) && start - open.finish <= merge_gap
            open.operations << op
            open.finish = [ open.finish, finish ].max
          else
            open = Group.new([ op ], start, finish, depth)
            open_by_depth[depth] = open
            groups << open
          end
        end

        groups
      end

      def same_kind?(a, b)
        a.operation_type == b.operation_type && operation_label(a) == operation_label(b)
      end

      def operation_label(operation)
        operation.respond_to?(:label) ? operation.label : nil
      end

      def bar_for(group)
        usable_pct = 100 - px_to_pct
        total = group.operations.sum { |op| op.duration.to_f }
        left_pct = ((group.start - @min_start) / @total_duration) * usable_pct + px_to_pct / 2
        width_pct = [ ((group.finish - group.start) / @total_duration) * usable_pct, 0 ].max

        OperationBar.new(
          group.operations.max_by { |op| op.duration.to_f },
          total.round(0),
          left_pct.round(PCT_PRECISION),
          width_pct.round(PCT_PRECISION),
          group.depth,
          group.operations.size,
          total
        )
      end

      def build_depth_map
        order_to_depth = present_lane_orders.each_with_index.to_h
        Hash.new { |map, type| map[type] = order_to_depth[lane_info(type)[:order]] || 0 }
      end

      def build_lane_labels
        seen = {}
        present_lane_orders.each_with_index.filter_map do |order, depth|
          label = LANE_DISPLAY.find { |_, v| v[:order] == order }&.last&.dig(:label) || "Other"
          next if seen[depth]
          seen[depth] = true
          [ depth, label ]
        end
      end

      def present_lane_orders
        @present_lane_orders ||= @operations
          .map { |op| lane_info(op.operation_type)[:order] }
          .uniq
          .sort
      end

      def lane_info(operation_type)
        LANE_DISPLAY[operation_type] || { label: "Other", order: 99 }
      end

      def px_to_pct
        (HORIZONTAL_OFFSET_PX.to_f / 1000) * 100
      end
    end
  end
end
