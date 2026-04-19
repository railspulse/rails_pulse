module RailsPulse
  module Stats
    class CleanupStatsReporter
      attr_reader :output, :config

      def self.report(output: $stdout)
        new(output: output).report
      end

      def initialize(output: $stdout)
        @output = output
        @config = RailsPulse.configuration
      end

      def report
        print_configuration
        print_table_sizes
        print_old_records_count if config.full_retention_period
      end

      private

      def print_configuration
        output.puts "Rails Pulse Cleanup Configuration:"
        output.puts "  Cleanup enabled: #{config.archiving_enabled}"
        output.puts "  Retention period: #{config.full_retention_period}"
        output.puts "  Table limits: #{config.max_table_records}"
        output.puts
      end

      def print_table_sizes
        output.puts "Current table sizes:"

        table_models.each do |table_name, model_name|
          print_table_count(table_name, model_name)
        end
      end

      def print_table_count(table_name, model_name)
        model_class = model_name.constantize
        count = model_class.count
        limit = config.max_table_records[table_name.to_sym]
        status = limit && count > limit ? " (OVER LIMIT)" : ""
        output.puts "  #{table_name}: #{count} records#{status}"
      rescue NameError
        output.puts "  #{table_name}: Model not found"
      rescue => e
        output.puts "  #{table_name}: Error - #{e.message}"
      end

      def print_old_records_count
        cutoff_time = config.full_retention_period.ago
        output.puts
        output.puts "Records older than #{cutoff_time}:"

        old_requests = RailsPulse::Request.where("occurred_at < ?", cutoff_time).count
        old_operations = RailsPulse::Operation.where("occurred_at < ?", cutoff_time).count
        output.puts "  rails_pulse_requests: #{old_requests} old records"
        output.puts "  rails_pulse_operations: #{old_operations} old records"
      rescue => e
        output.puts "  Error calculating old records: #{e.message}"
      end

      def table_models
        {
          "rails_pulse_requests" => "RailsPulse::Request",
          "rails_pulse_operations" => "RailsPulse::Operation",
          "rails_pulse_routes" => "RailsPulse::Route",
          "rails_pulse_queries" => "RailsPulse::Query"
        }
      end
    end
  end
end
