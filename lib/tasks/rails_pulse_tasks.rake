namespace :rails_pulse do
  desc "Copies Rails Pulse migrations to the application."
  task :install_migrations do
    source_dir = File.expand_path("../../../db/migrate", __FILE__)
    destination_dir = File.join(Rails.root, "db/migrate")

    # Define the correct migration order
    migration_order = [
      "create_routes.rb",
      "create_requests.rb",
      "create_queries.rb",
      "create_operations.rb"
    ]

    puts "Copying migrations..."
    base_time = Time.now.utc

    migration_order.each_with_index do |migration_name, index|
      # Find the source migration file
      source_file = Dir.glob(File.join(source_dir, "*#{migration_name}")).first
      next unless source_file

      # Generate new timestamp
      timestamp = (base_time + index.seconds).strftime("%Y%m%d%H%M%S")
      new_filename = "#{timestamp}_#{migration_name.gsub('.rb', '')}.rails_pulse.rb"
      destination_file = File.join(destination_dir, new_filename)

      # Check if any version of this migration already exists
      existing_migration = Dir.glob(File.join(destination_dir, "*#{migration_name.gsub('.rb', '')}*")).first

      if existing_migration
        puts "Skipping existing migration: #{File.basename(existing_migration)}"
      else
        FileUtils.cp(source_file, destination_file)
        puts "Copied migration: #{new_filename}"
      end
    end
  end

  desc "Copies Rails Pulse example configuration to the application."
  task :install_config do
    source_file = File.expand_path("../../../lib/generators/rails_pulse/templates/rails_pulse.rb", __FILE__)
    destination_file = File.join(Rails.root, "config/initializers/rails_pulse.rb")

    if File.exist?(destination_file)
      puts "Config already exists at #{destination_file}, skipping."
    else
      FileUtils.cp(source_file, destination_file)
      puts "Copied example config to #{destination_file}"
    end
  end

  desc "Runs all install tasks for Rails Pulse (migrations and config)."
  task install: [ :install_migrations, :install_config ]

  desc "Performs data cleanup based on configured retention policies."
  task cleanup: :environment do
    puts "Starting Rails Pulse data cleanup..."

    config = RailsPulse.configuration

    unless config.archiving_enabled
      puts "Cleanup is disabled (archiving_enabled = false). Exiting."
      exit
    end

    stats = RailsPulse::CleanupService.perform

    puts "Cleanup completed!"
    puts "Records deleted:"
    puts "  Time-based cleanup: #{stats[:time_based].values.sum}"
    puts "  Count-based cleanup: #{stats[:count_based].values.sum}"
    puts "  Total: #{stats[:total_deleted]}"

    if stats[:total_deleted] > 0
      puts "\nBreakdown by table:"
      stats[:time_based].each do |table, count|
        puts "  #{table} (time-based): #{count}" if count > 0
      end
      stats[:count_based].each do |table, count|
        puts "  #{table} (count-based): #{count}" if count > 0
      end
    end
  rescue => e
    puts "Cleanup failed: #{e.message}"
    puts e.backtrace.join("\n") if ENV["VERBOSE"]
    exit 1
  end

  desc "Shows current table sizes and cleanup configuration."
  task cleanup_stats: :environment do
    config = RailsPulse.configuration

    puts "Rails Pulse Cleanup Configuration:"
    puts "  Cleanup enabled: #{config.archiving_enabled}"
    puts "  Retention period: #{config.full_retention_period}"
    puts "  Table limits: #{config.max_table_records}"
    puts

    puts "Current table sizes:"

    tables = {
      "rails_pulse_requests" => "RailsPulse::Request",
      "rails_pulse_operations" => "RailsPulse::Operation",
      "rails_pulse_routes" => "RailsPulse::Route",
      "rails_pulse_queries" => "RailsPulse::Query"
    }

    tables.each do |table_name, model_name|
      begin
        model_class = model_name.constantize
        count = model_class.count
        limit = config.max_table_records[table_name.to_sym]
        status = limit && count > limit ? " (OVER LIMIT)" : ""
        puts "  #{table_name}: #{count} records#{status}"
      rescue NameError
        puts "  #{table_name}: Model not found"
      rescue => e
        puts "  #{table_name}: Error - #{e.message}"
      end
    end

    if config.full_retention_period
      cutoff_time = config.full_retention_period.ago
      puts
      puts "Records older than #{cutoff_time}:"

      begin
        old_requests = RailsPulse::Request.where("occurred_at < ?", cutoff_time).count
        old_operations = RailsPulse::Operation.where("occurred_at < ?", cutoff_time).count
        puts "  rails_pulse_requests: #{old_requests} old records"
        puts "  rails_pulse_operations: #{old_operations} old records"
      rescue => e
        puts "  Error calculating old records: #{e.message}"
      end
    end
  end
end
