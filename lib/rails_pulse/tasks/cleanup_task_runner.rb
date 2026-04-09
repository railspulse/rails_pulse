module RailsPulse
  module Tasks
    class CleanupTaskRunner
      attr_reader :output, :config

      def self.run(output: $stdout)
        new(output: output).run
      end

      def initialize(output: $stdout)
        @output = output
        @config = RailsPulse.configuration
      end

      def run
        output.puts "Starting Rails Pulse data cleanup..."

        unless config.archiving_enabled
          output.puts "Cleanup is disabled (archiving_enabled = false). Exiting."
          return false
        end

        stats = perform_cleanup
        print_results(stats)
        true
      rescue => e
        handle_error(e)
        false
      end

      private

      def perform_cleanup
        RailsPulse::CleanupService.perform
      end

      def print_results(stats)
        output.puts "Cleanup completed!"
        output.puts "Records deleted:"
        output.puts "  Time-based cleanup: #{stats[:time_based].values.sum}"
        output.puts "  Count-based cleanup: #{stats[:count_based].values.sum}"
        output.puts "  Total: #{stats[:total_deleted]}"

        print_breakdown(stats) if stats[:total_deleted] > 0
      end

      def print_breakdown(stats)
        output.puts "\nBreakdown by table:"

        stats[:time_based].each do |table, count|
          output.puts "  #{table} (time-based): #{count}" if count > 0
        end

        stats[:count_based].each do |table, count|
          output.puts "  #{table} (count-based): #{count}" if count > 0
        end
      end

      def handle_error(error)
        output.puts "Cleanup failed: #{error.message}"
        output.puts error.backtrace.join("\n") if ENV["VERBOSE"]
      end
    end
  end
end
