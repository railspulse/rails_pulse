require_relative "routes"
require_relative "queries"
require_relative "requests"
require_relative "background_jobs"
require_relative "job_summaries"
require_relative "query_analysis"
require_relative "additional_users_posts"
require_relative "deployments"

module RailsPulse
  module Seeds
    module HistoricalData
      def self.seed!
        puts "\nGenerating Rails Pulse historical data..."

        SeedConfig.display_config
        SeedConfig.validate_config

        clear_existing_data
        routes = Routes.seed!
        queries = Queries.seed!
        Deployments.seed!(days_ago: SeedConfig.days_ago)

        Requests.seed!(routes, queries, request_count: SeedConfig.request_count)

        jobs = BackgroundJobs.seed!(queries)
        JobSummaries.seed!(jobs)

        AdditionalUsersAndPosts.seed!
        generate_summaries

        historical_start_time = ::RailsPulse::Request.minimum(:occurred_at)&.beginning_of_day || SeedConfig.days_ago.days.ago
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
        ::RailsPulse::Deployment.delete_all
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
        strategy = SeedConfig.summary_strategy

        case strategy
        when "none"
          puts "Skipping summary backfill (strategy: none)"
        when "minimal"
          backfill_minimal(end_time)
        when "smart"
          backfill_smart(start_time, end_time)
        when "complete"
          backfill_complete(start_time, end_time)
        else
          puts "⚠️  Unknown summary strategy '#{strategy}', using minimal"
          backfill_minimal(end_time)
        end
      end

      def self.backfill_minimal(end_time)
        print "Backfilling hour summaries (last 26 hours, strategy: minimal)"
        hourly_start = 26.hours.ago
        ::RailsPulse::BackfillSummariesJob.perform_now(hourly_start, end_time, [ "hour" ])
        puts " ✓"
      end

      def self.backfill_smart(start_time, end_time)
        # Backfill enough to cover retention period + buffer
        retention_days = 14 # Could read from RailsPulse config
        smart_start = (retention_days + 2).days.ago

        # Only backfill what exists
        actual_start = [ start_time, smart_start ].max

        print "Backfilling day summaries (strategy: smart)"
        ::RailsPulse::BackfillSummariesJob.perform_now(actual_start, end_time, [ "day" ])
        puts " ✓"

        print "Backfilling hour summaries (#{retention_days + 2} days, strategy: smart)"
        ::RailsPulse::BackfillSummariesJob.perform_now(actual_start, end_time, [ "hour" ])
        puts " ✓"
      end

      def self.backfill_complete(start_time, end_time)
        print "Backfilling day summaries (full period, strategy: complete)"
        ::RailsPulse::BackfillSummariesJob.perform_now(start_time, end_time, [ "day" ])
        puts " ✓"

        print "Backfilling hour summaries (full period, strategy: complete)"
        ::RailsPulse::BackfillSummariesJob.perform_now(start_time, end_time, [ "hour" ])
        puts " ✓"
      end
    end
  end
end
