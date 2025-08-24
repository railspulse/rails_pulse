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
      return
    end

    historical_end_time = Time.current

    # Generate daily summaries from beginning of data
    puts "\nCreating daily summaries from #{historical_start_time.strftime('%B %d, %Y')} to #{historical_end_time.strftime('%B %d, %Y')}"
    RailsPulse::BackfillSummariesJob.perform_now(historical_start_time, historical_end_time, [ "day" ])

    # Generate hourly summaries for past 26 hours
    puts "\nCreating hourly summaries for the past 26 hours..."
    hourly_start_time = 26.hours.ago
    hourly_end_time = Time.current

    puts "From #{hourly_start_time.strftime('%B %d at %I:%M %p')} to #{hourly_end_time.strftime('%B %d at %I:%M %p')}"
    RailsPulse::BackfillSummariesJob.perform_now(hourly_start_time, hourly_end_time, [ "hour" ])

    puts "\nSummary backfill completed!"
    puts "Total summaries: #{RailsPulse::Summary.count}"
    puts "\nTo keep summaries up to date, schedule RailsPulse::SummaryJob to run hourly"
  end
end
