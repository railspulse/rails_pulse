require "rails_pulse/version"
require "rails_pulse/middleware/request_collector"
require "rails_pulse/subscribers/request_subscriber"
require "rails_pulse/subscribers/operation_subscriber"
require "request_store"

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

    initializer "rails_pulse.importmap", before: "importmap" do |app|
      app.config.importmap.paths << Engine.root.join("config/importmap.rb")
    end

    initializer "rails_pulse.assets" do |app|
      app.config.assets.paths << Engine.root.join("app/javascript")
      if Rails.env.development?
        app.config.importmap.cache_sweepers << Engine.root.join("app/javascript")
        app.config.assets.digest = false
      end
    end

    initializer "rails_pulse.middleware" do |app|
      app.middleware.use RailsPulse::Middleware::RequestCollector
    end

    initializer "rails_pulse.notifications" do
      RailsPulse::Subscribers::RequestSubscriber.subscribe!
    end

    initializer "rails_pulse.operation_notifications" do
      RailsPulse::Subscribers::OperationSubscriber.subscribe!
    end
  end
end
