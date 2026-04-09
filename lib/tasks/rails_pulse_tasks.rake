namespace :rails_pulse do
  desc "Copies Rails Pulse migrations to the application."
  task :install_migrations do
    RailsPulse::Installers::MigrationInstaller.install
  end

  desc "Copies Rails Pulse example configuration to the application."
  task :install_config do
    RailsPulse::Installers::ConfigInstaller.install
  end

  desc "Runs all install tasks for Rails Pulse (migrations and config)."
  task install: [ :install_migrations, :install_config ]

  desc "Performs data cleanup based on configured retention policies."
  task cleanup: :environment do
    success = RailsPulse::Tasks::CleanupTaskRunner.run
    exit 1 unless success
  end

  desc "Shows current table sizes and cleanup configuration."
  task cleanup_stats: :environment do
    RailsPulse::Stats::CleanupStatsReporter.report
  end
end
