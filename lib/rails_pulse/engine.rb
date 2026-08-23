require "rails_pulse/version"
require "rails_pulse/statistics"
require "rails_pulse/middleware/request_collector"
require "rails_pulse/middleware/asset_server"
require "rails_pulse/subscribers/operation_subscriber"
require "rails_pulse/job_run_collector"
require "rails_pulse/active_job_extensions"
require "rails_pulse/extensions/active_record"
require "request_store"
require "rack/static"
require "ransack"

module RailsPulse
  # Manually load services to avoid Zeitwerk autoload issues
  autoload :SqlQueryNormalizer, File.expand_path("../../app/services/rails_pulse/sql_query_normalizer", __dir__)
  autoload :SummaryService, File.expand_path("../../app/services/rails_pulse/summary_service", __dir__)
  autoload :QueryAnalysisService, File.expand_path("../../app/services/rails_pulse/query_analysis_service", __dir__)
  autoload :TagFilterService, File.expand_path("../../app/services/rails_pulse/tag_filter_service", __dir__)
  autoload :OperationSuggestions, File.expand_path("../../app/services/rails_pulse/operation_suggestions", __dir__)

  # Analysis services
  module Analysis
    autoload :BacktraceAnalyzer, File.expand_path("../../app/services/rails_pulse/analysis/backtrace_analyzer", __dir__)
    autoload :BaseAnalyzer, File.expand_path("../../app/services/rails_pulse/analysis/base_analyzer", __dir__)
    autoload :ExplainPlanAnalyzer, File.expand_path("../../app/services/rails_pulse/analysis/explain_plan_analyzer", __dir__)
    autoload :IndexRecommendationEngine, File.expand_path("../../app/services/rails_pulse/analysis/index_recommendation_engine", __dir__)
    autoload :NPlusOneDetector, File.expand_path("../../app/services/rails_pulse/analysis/n_plus_one_detector", __dir__)
    autoload :QueryCharacteristicsAnalyzer, File.expand_path("../../app/services/rails_pulse/analysis/query_characteristics_analyzer", __dir__)
    autoload :SuggestionGenerator, File.expand_path("../../app/services/rails_pulse/analysis/suggestion_generator", __dir__)
  end

  # Installer services
  module Installers
    autoload :MigrationInstaller, File.expand_path("installers/migration_installer", __dir__)
    autoload :ConfigInstaller, File.expand_path("installers/config_installer", __dir__)
  end

  # Stats reporting services
  module Stats
    autoload :CleanupStatsReporter, File.expand_path("stats/cleanup_stats_reporter", __dir__)
  end

  # Task runners
  module Tasks
    autoload :CleanupTaskRunner, File.expand_path("tasks/cleanup_task_runner", __dir__)
  end

  class Engine < ::Rails::Engine
    isolate_namespace RailsPulse

    # Tell Zeitwerk to ignore services directory since we manually autoload them
    initializer "rails_pulse.ignore_services", before: :set_autoload_paths do
      Rails.autoloaders.main.ignore(root.join("app/services")) if Rails.respond_to?(:autoloaders)
    end

    # Load Rake tasks
    rake_tasks do
      Dir.glob(File.expand_path("../tasks/**/*.rake", __FILE__)).each { |file| load file }
    end

    # Register the install generator
    generators do
      require "generators/rails_pulse/install_generator"
    end

    initializer "rails_pulse.assets" do |app|
      # Dashboard assets are bundled at gem build time. They are not registered
      # with Sprockets (re-minifying the 2 MB bundle OOMs small hosts — #190).
      # assets:precompile copies them into public/assets for CDN/CSP; the
      # middleware is the development / no-pipeline fallback.
      assets_path = Engine.root.join("public")
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
