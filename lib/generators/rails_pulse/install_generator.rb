module RailsPulse
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Copies Rails Pulse migrations to the application."
      def copy_migrations
        rake "rails_pulse:install:migrations"
      end

      desc "Copies Rails Pulse example configuration file to the application."
      def copy_initializer
        copy_file "rails_pulse.rb", "config/initializers/rails_pulse.rb"
      end
    end
  end
end
