require "rails_pulse/version"
require "rails_pulse/middleware/request_collector"
require "rails_pulse/middleware/asset_server"
require "rails_pulse/subscribers/operation_subscriber"
require "request_store"
require "rack/static"
require "rails_charts"
require "ransack"
require "pagy"
require "turbo-rails"
require "groupdate"

module RailsPulse
  class Engine < ::Rails::Engine
    isolate_namespace RailsPulse

    # Prevent rails_charts from polluting the global ActionView namespace
    # This MUST happen before any initializers run to avoid conflicts with host apps
    # that use Chartkick or other chart libraries
    if defined?(RailsCharts::Engine)
      # Find and remove the rails_charts.helpers initializer
      RailsCharts::Engine.initializers.delete_if do |init|
        init.name == "rails_charts.helpers"
      end
    end


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

    initializer "rails_pulse.rails_charts_theme" do
      RailsCharts.options[:theme] = "railspulse"
    end

    # Manually include RailsCharts helpers only in RailsPulse views
    # This ensures rails_charts methods are only available in RailsPulse namespace,
    # not in the host application
    initializer "rails_pulse.include_rails_charts_helpers" do
      ActiveSupport.on_load :action_view do
        if defined?(RailsCharts::Helpers) && defined?(RailsPulse::ChartHelper)
          unless RailsPulse::ChartHelper.include?(RailsCharts::Helpers)
            RailsPulse::ChartHelper.include(RailsCharts::Helpers)
          end
        end
      end
    end


    initializer "rails_pulse.ransack", after: "ransack.initialize" do
      # Ensure Ransack is loaded before our models
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
