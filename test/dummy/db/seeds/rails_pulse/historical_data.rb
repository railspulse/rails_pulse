require_relative "routes"
require_relative "queries"
require_relative "requests"
require_relative "background_jobs"
require_relative "job_summaries"
require_relative "query_analysis"
require_relative "additional_users_posts"

module RailsPulse
  module Seeds
    module HistoricalData
      def self.seed!
        puts "\nGenerating Rails Pulse historical data..."

        clear_existing_data
        routes = Routes.seed!
        queries = Queries.seed!

        request_count = ENV["HISTORICAL_REQUEST_COUNT"]&.to_i || 5000
        Requests.seed!(routes, queries, request_count: request_count)

        jobs = BackgroundJobs.seed!(queries)
        JobSummaries.seed!(jobs)

        AdditionalUsersAndPosts.seed!
        generate_summaries

        historical_start_time = ::RailsPulse::Request.minimum(:occurred_at)&.beginning_of_day || 5.weeks.ago
        historical_end_time = Time.current

        QueryAnalysis.seed!(queries, routes, historical_start_time, historical_end_time)

        backfill_summaries(historical_start_time, historical_end_time)
      end

      private

      def self.clear_existing_data
        print "Clearing existing Rails Pulse data"
        ::RailsPulse::Operation.delete_all
        ::RailsPulse::Request.delete_all
        ::RailsPulse::JobRun.delete_all
        ::RailsPulse::Job.delete_all
        ::RailsPulse::Query.delete_all
        ::RailsPulse::Route.delete_all
        ::RailsPulse::Summary.delete_all
        puts " ✓"
      end

      def self.generate_summaries
        print "Generating recent summaries"
        (0..3).each do |hours_ago|
          target_hour = hours_ago.hours.ago.beginning_of_hour
          ::RailsPulse::SummaryJob.perform_now(target_hour)
          print "."
        end
        puts " ✓"
      end

      def self.backfill_summaries(start_time, end_time)
        print "Backfilling day summaries"
        ::RailsPulse::BackfillSummariesJob.perform_now(start_time, end_time, [ "day" ])
        puts " ✓"

        print "Backfilling hour summaries (last 26 hours)"
        hourly_start = 26.hours.ago
        ::RailsPulse::BackfillSummariesJob.perform_now(hourly_start, end_time, [ "hour" ])
        puts " ✓"
      end
    end
  end
end
