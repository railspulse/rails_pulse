namespace :db do
  namespace :schema do
    desc "Load Rails Pulse schema"
    task load_rails_pulse: :environment do
      schema_file = Rails.root.join("db/rails_pulse_schema.rb")
      if schema_file.exist?
        load schema_file
        puts "Rails Pulse schema loaded successfully"
      else
        puts "Rails Pulse schema file not found. Run: rails generate rails_pulse:install"
      end
    end
  end

  # Hook into common database tasks to load schema
  task prepare: "schema:load_rails_pulse"
  task setup: "schema:load_rails_pulse"
end
