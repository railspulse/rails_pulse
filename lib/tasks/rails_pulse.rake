namespace :db do
  namespace :schema do
    desc "Load Rails Pulse schema (for separate database setup only)"
    task load_rails_pulse: :environment do
      schema_file = Rails.root.join("db/rails_pulse_schema.rb")

      # Only load schema if using separate database setup
      if separate_database_setup?
        if schema_file.exist?
          load schema_file
          puts "Rails Pulse schema loaded successfully"
        else
          puts "Rails Pulse schema file not found. Run: rails generate rails_pulse:install --database=separate"
        end
      else
        puts "Single database setup detected. Rails Pulse tables managed via regular migrations."
      end
    end
  end

  # Hook into common database tasks only for separate database setup
  task prepare: :environment do
    Rake::Task["db:schema:load_rails_pulse"].invoke if separate_database_setup?
  end

  task setup: :environment do
    Rake::Task["db:schema:load_rails_pulse"].invoke if separate_database_setup?
  end
end

# Helper function to detect database setup type
def separate_database_setup?
  # Check if there's a rails_pulse_migrate directory (indicates separate database)
  Rails.root.join("db/rails_pulse_migrate").exist? ||
  # Check if database.yml has rails_pulse configuration
  (Rails.application.config.database_configuration.dig(Rails.env, "rails_pulse").present?)
end

namespace :rails_pulse do
  desc "Backfill summary data from existing requests and operations"
  task backfill_summaries: :environment do
    puts "Starting Rails Pulse summary backfill..."

    # Find earliest data
    earliest_request = RailsPulse::Request.minimum(:occurred_at)
    earliest_operation = RailsPulse::Operation.minimum(:occurred_at)

    historical_start_time = if earliest_request && earliest_operation
      [ earliest_request, earliest_operation ].min.beginning_of_day
    elsif earliest_request
      earliest_request.beginning_of_day
    elsif earliest_operation
      earliest_operation.beginning_of_day
    else
      puts "No Rails Pulse data found - skipping summary generation"
      next
    end

    historical_end_time = Time.current

    # Generate hourly and daily summaries from beginning of data
    puts "\nCreating hourly and daily summaries from #{historical_start_time.strftime('%B %d, %Y')} to #{historical_end_time.strftime('%B %d, %Y')}"
    RailsPulse::BackfillSummariesJob.perform_now(historical_start_time, historical_end_time, [ "hour", "day" ])

    puts "\nSummary backfill completed!"
    puts "Total summaries: #{RailsPulse::Summary.count}"
    puts "\nTo keep summaries up to date, schedule RailsPulse::SummaryJob to run hourly"
  end

  desc "Assign orphaned routes (with no host) to a specified host. Usage: rails rails_pulse:backfill_hosts[example.com]"
  task :backfill_hosts, [:hostname] => :environment do |_t, args|
    hostname = args[:hostname]

    if hostname.blank?
      puts "Usage: rails rails_pulse:backfill_hosts[example.com]"
      puts ""
      puts "This assigns all routes with no host to the specified hostname."
      puts "Useful after upgrading from a version that didn't track hosts."
      next
    end

    orphaned_routes = RailsPulse::Route.where(host_id: nil)
    count = orphaned_routes.count

    if count.zero?
      puts "No orphaned routes found — all routes already have a host assigned."
      next
    end

    host = RailsPulse::Host.find_or_create_by!(name: hostname)
    puts "Assigning #{count} orphaned route(s) to host '#{hostname}'..."

    assigned = 0
    merged = 0

    orphaned_routes.find_each do |route|
      existing = RailsPulse::Route.find_by(method: route.method, path: route.path, host_id: host.id)

      if existing
        # Merge: move requests/summaries to the existing route, then delete the orphan
        route.requests.update_all(route_id: existing.id)
        route.summaries.update_all(summarizable_id: existing.id)
        route.destroy
        merged += 1
      else
        route.update_columns(host_id: host.id)
        assigned += 1
      end
    end

    puts "Done! Assigned #{assigned} route(s), merged #{merged} duplicate(s) into '#{hostname}'."
  end
end
