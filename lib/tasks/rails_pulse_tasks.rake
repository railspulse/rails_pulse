namespace :rails_pulse do
  desc "Copies Rails Pulse migrations to the application."
  task :install_migrations do
    source_dir = File.expand_path("../../../db/migrate", __FILE__)
    destination_dir = File.join(Rails.root, "db/migrate")

    puts "Copying migrations..."
    puts File.join(source_dir, "*.rb")
    Dir.glob(File.join(source_dir, "*.rb")).each do |migration_file|
      puts "Processing migration: #{migration_file}"
      filename = File.basename(migration_file)
      destination_file = File.join(destination_dir, filename)

      unless File.exist?(destination_file)
        FileUtils.cp(migration_file, destination_file)
        puts "Copied migration: #{filename}"
      else
        puts "Skipping existing migration: #{filename}"
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
end
