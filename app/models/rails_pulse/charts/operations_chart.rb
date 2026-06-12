module RailsPulse
  module Charts
    class OperationsChart
      OperationBar = Struct.new(:operation, :duration, :left_pct, :width_pct, :depth)

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

      attr_reader :bars, :min_start, :max_end, :total_duration, :max_depth, :lane_labels

      HORIZONTAL_OFFSET_PX = 20

      def initialize(operations)
        @operations = operations.to_a
        @min_start = @operations.map(&:start_time).min || 0
        @max_end = @operations.map { |op| op.start_time + op.duration }.max || 1
        @total_duration = [ @max_end - @min_start, 0 ].max.nonzero? || 1
        @bars = build_bars
        @max_depth = @bars.map(&:depth).max || 0
        @lane_labels = build_lane_labels
      end

      private

      def build_bars
        depth_map = build_depth_map
        @operations.map do |operation|
          left_pct = ((operation.start_time - @min_start).to_f / @total_duration) * (100 - px_to_pct) + px_to_pct / 2
          width_pct = [ (operation.duration.to_f / @total_duration) * (100 - px_to_pct), 0 ].max
          OperationBar.new(operation, operation.duration.round(0), left_pct, width_pct, depth_map[operation.object_id])
        end
      end

      def build_depth_map
        order_to_depth = present_lane_orders.each_with_index.to_h
        depths = {}
        @operations.each do |op|
          order = lane_info(op.operation_type)[:order]
          depths[op.object_id] = order_to_depth[order] || 0
        end
        depths
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
