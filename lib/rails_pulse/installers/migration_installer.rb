module RailsPulse
  module Installers
    class MigrationInstaller
      attr_reader :output, :stats

      def self.install(output: $stdout)
        new(output: output).install
      end

      def initialize(output: $stdout)
        @output = output
        @stats = { copied: [], skipped: [] }
      end

      def install
        output.puts "Copying migrations..."

        migration_order.each_with_index do |migration_name, index|
          process_migration(migration_name, index)
        end

        @stats
      end

      private

      def process_migration(migration_name, index)
        source_file = find_source_file(migration_name)
        return unless source_file

        destination_file = build_destination_path(migration_name, index)

        if migration_exists?(migration_name)
          skip_migration(migration_name)
        else
          copy_migration(source_file, destination_file, migration_name)
        end
      end

      def find_source_file(migration_name)
        Dir.glob(File.join(source_dir, "*#{migration_name}")).first
      end

      def migration_exists?(migration_name)
        pattern = File.join(destination_dir, "*#{migration_name.gsub('.rb', '')}*")
        Dir.glob(pattern).any?
      end

      def skip_migration(migration_name)
        existing = Dir.glob(File.join(destination_dir, "*#{migration_name.gsub('.rb', '')}*")).first
        filename = existing ? File.basename(existing) : migration_name
        output.puts "Skipping existing migration: #{filename}"
        @stats[:skipped] << migration_name
      end

      def copy_migration(source_file, destination_file, migration_name)
        FileUtils.cp(source_file, destination_file)
        output.puts "Copied migration: #{File.basename(destination_file)}"
        @stats[:copied] << migration_name
      end

      def build_destination_path(migration_name, index)
        timestamp = (base_time + index.seconds).strftime("%Y%m%d%H%M%S")
        new_filename = "#{timestamp}_#{migration_name.gsub('.rb', '')}.rails_pulse.rb"
        File.join(destination_dir, new_filename)
      end

      def migration_order
        [
          "create_routes.rb",
          "create_requests.rb",
          "create_queries.rb",
          "create_operations.rb"
        ]
      end

      def source_dir
        File.expand_path("../../../../db/migrate", __FILE__)
      end

      def destination_dir
        File.join(Rails.root, "db/migrate")
      end

      def base_time
        @base_time ||= Time.now.utc
      end
    end
  end
end
