require "rails_pulse/version"
require "rails_pulse/middleware/request_collector"
require "rails_pulse/middleware/asset_server"
require "rails_pulse/subscribers/operation_subscriber"
require "rails_pulse/job_run_collector"
require "rails_pulse/active_job_extensions"
require "request_store"
require "rack/static"
require "ransack"
require "pagy"
require "turbo-rails"
require "groupdate"

module RailsPulse
  class Engine < ::Rails::Engine
    isolate_namespace RailsPulse

    # Load Rake tasks
    rake_tasks do
      Dir.glob(File.expand_path("../tasks/**/*.rake", __FILE__)).each { |file| load file }
    end

    # Register the install generator
    generators do
      require "generators/rails_pulse/install_generator"
    end

    initializer "rails_pulse.static_assets", before: "sprockets.environment" do |app|
      # Configure Rack::Static middleware to serve pre-compiled assets
      assets_path = Engine.root.join("public")

      # Add custom middleware for serving Rails Pulse assets with proper headers
      # Insert after Rack::Runtime but before ActionDispatch::Static for better compatibility
      app.middleware.insert_after Rack::Runtime, RailsPulse::Middleware::AssetServer,
        assets_path.to_s,
        {
          urls: [ "/rails-pulse-assets" ],
          headers: Engine.asset_headers
        }
    end

    initializer "rails_pulse.middleware" do |app|
      app.middleware.use RailsPulse::Middleware::RequestCollector
    end

    initializer "rails_pulse.operation_notifications" do
      RailsPulse::Subscribers::OperationSubscriber.subscribe!
    end

    initializer "rails_pulse.ransack", after: "ransack.initialize" do
      # Ensure Ransack is loaded before our models
    end

    initializer "rails_pulse.active_job" do
      ActiveSupport.on_load(:active_job) do
        include RailsPulse::ActiveJobExtensions
      end
    end

    initializer "rails_pulse.configure_sidekiq", after: "rails_pulse.active_job" do
      if defined?(Sidekiq) && RailsPulse.configuration.job_adapters.dig(:sidekiq, :enabled)
        require "rails_pulse/adapters/sidekiq_middleware"
        Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add RailsPulse::Adapters::SidekiqMiddleware
          end
        end
      end
    end

    initializer "rails_pulse.configure_delayed_job", after: "rails_pulse.active_job" do
      if defined?(Delayed::Job) && RailsPulse.configuration.job_adapters.dig(:delayed_job, :enabled)
        require "rails_pulse/adapters/delayed_job_plugin"
        Delayed::Worker.plugins << RailsPulse::Adapters::DelayedJobPlugin
      end
    end

    initializer "rails_pulse.database_configuration", before: "active_record.initialize_timezone" do
      # Ensure database configuration is applied early in the initialization process
      # This allows models to properly connect to configured databases
    end

    initializer "rails_pulse.timezone" do
      # Configure Rails Pulse to always use UTC for consistent time operations
      # This prevents Groupdate timezone mismatch errors across different host applications
      # Note: We don't set Time.zone_default as it would affect the entire application
      # Instead, we explicitly use time_zone: "UTC" in all groupdate calls
    end

    initializer "rails_pulse.disable_turbo" do
      # Disable Turbo navigation globally for Rails Pulse to avoid CSP issues with charts
      # This ensures all navigation within Rails Pulse uses full page refreshes
      ActiveSupport.on_load(:action_view) do
        ActionView::Helpers::UrlHelper.module_eval do
          alias_method :original_link_to, :link_to

          def link_to(*args, &block)
            # Only modify links within Rails Pulse namespace
            if respond_to?(:controller) && controller.class.name.start_with?("RailsPulse::")
              options = args.extract_options!
              options[:data] ||= {}
              options[:data][:turbo] = false unless options[:data].key?(:turbo)
              args << options
            end
            original_link_to(*args, &block)
          end
        end
      end
    end

    # CSP helper methods
    def self.csp_sources
      {
        script_src: [ "'self'", "'nonce-'" ],
        style_src: [ "'self'", "'nonce-'" ],
        img_src: [ "'self'", "data:" ]
      }
    end

    private

    def self.asset_headers
      {
        "Cache-Control" => "public, max-age=31536000, immutable",
        "Vary" => "Accept-Encoding"
      }
    end
  end
end
