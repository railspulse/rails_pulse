module RailsPulse
  module Installers
    class ConfigInstaller
      attr_reader :output

      def self.install(output: $stdout)
        new(output: output).install
      end

      def initialize(output: $stdout)
        @output = output
      end

      def install
        if config_exists?
          skip_existing_config
          { status: :skipped, path: destination_file }
        else
          copy_config
          { status: :copied, path: destination_file }
        end
      end

      private

      def config_exists?
        File.exist?(destination_file)
      end

      def skip_existing_config
        output.puts "Config already exists at #{destination_file}, skipping."
      end

      def copy_config
        FileUtils.cp(source_file, destination_file)
        output.puts "Copied example config to #{destination_file}"
      end

      def source_file
        File.expand_path("../../../../lib/generators/rails_pulse/templates/rails_pulse.rb", __FILE__)
      end

      def destination_file
        @destination_file ||= File.join(Rails.root, "config/initializers/rails_pulse.rb")
      end
    end
  end
end
