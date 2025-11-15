module RailsPulse
  module Charts
    class OperationsChart
      OperationBar = Struct.new(:operation, :duration, :left_pct, :width_pct)

      attr_reader :bars, :min_start, :max_end, :total_duration

      HORIZONTAL_OFFSET_PX = 20

      def initialize(operations)
        @operations = operations
        @min_start = @operations.map(&:start_time).min || 0
        @max_end = @operations.map { |op| op.start_time + op.duration }.max || 1
        @total_duration = (@max_end - @min_start).nonzero? || 1
        @bars = build_bars
      end

      private

      def build_bars
        @operations.map do |operation|
          left_pct = ((operation.start_time - @min_start).to_f / @total_duration) * (100 - px_to_pct) + px_to_pct / 2
          width_pct = (operation.duration.to_f / @total_duration) * (100 - px_to_pct)
          OperationBar.new(operation, operation.duration.round(0), left_pct, width_pct)
        end
      end

      def px_to_pct
        (HORIZONTAL_OFFSET_PX.to_f / 1000) * 100
      end
    end
  end
end
