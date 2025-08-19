#!/usr/bin/env ruby
# Generate historical daily stats for requests and queries for the past month
# Usage: bundle exec rails runner generate_historical_stats.rb

puts "Starting historical stats generation for the past month..."
start_time = Time.current

# Generate stats for the past 30 days
end_date = Date.current - 1.day # Yesterday (don't process today as it's incomplete)
start_date = end_date - 29.days # 30 days total

puts "Processing date range: #{start_date} to #{end_date}"

total_days = (end_date - start_date + 1).to_i
processed_days = 0
errors = []

(start_date..end_date).each do |date|
  puts "\n=== Processing #{date} (#{processed_days + 1}/#{total_days}) ==="

  begin
    # Process each hour of the day for requests and queries
    (0..23).each do |hour|
      target_hour = date.beginning_of_day + hour.hours

      # Skip future hours
      next if target_hour > Time.current

      print "  Hour #{hour.to_s.rjust(2, '0')}:00 - "

      # Run hourly job for this specific hour
      job_result = RailsPulse::HourlyStatsJob.new.perform(target_hour)

      requests_processed = job_result.dig(:requests, :requests_processed) || 0
      queries_processed = job_result.dig(:queries, :queries_processed) || 0

      puts "#{requests_processed} requests, #{queries_processed} queries"
    end

    # Run daily finalization job for this date
    print "  Finalizing daily aggregates - "
    daily_result = RailsPulse::DailyStatsJob.new.perform(date)

    requests_finalized = daily_result.dig(:requests, :requests_finalized) || 0
    queries_finalized = daily_result.dig(:queries, :queries_finalized) || 0

    puts "#{requests_finalized} requests, #{queries_finalized} queries finalized"

    processed_days += 1

  rescue => e
    error_msg = "Error processing #{date}: #{e.message}"
    puts "  ERROR: #{error_msg}"
    errors << error_msg
  end
end

# Summary
puts "\n" + "="*60
puts "HISTORICAL STATS GENERATION COMPLETE"
puts "="*60
puts "Date range: #{start_date} to #{end_date}"
puts "Days processed: #{processed_days}/#{total_days}"
puts "Processing time: #{(Time.current - start_time).round(2)} seconds"

if errors.any?
  puts "\nErrors encountered:"
  errors.each { |error| puts "  - #{error}" }
else
  puts "\n✅ All days processed successfully!"
end

# Show final stats
puts "\nFinal daily stats summary:"
requests_stats = RailsPulse::DailyStat.where(entity_type: "request", date: start_date..end_date)
queries_stats = RailsPulse::DailyStat.where(entity_type: "query", date: start_date..end_date)

puts "  Requests daily stats: #{requests_stats.count} records"
puts "  Queries daily stats: #{queries_stats.count} records"
puts "  Total requests processed: #{requests_stats.sum(:total_requests)}"
puts "  Total query operations processed: #{queries_stats.sum(:total_requests)}"

puts "\nHistorical stats generation completed! 🚀"
