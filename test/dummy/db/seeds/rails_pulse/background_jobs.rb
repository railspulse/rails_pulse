module RailsPulse
  module Seeds
    module BackgroundJobs
      JOB_DEFINITIONS = [
        {
          name: "UserMailerJob",
          queue_name: "mailers",
          base_duration: 80,
          variance: 40,
          error_rate: 0.01,
          runs_per_day: 50
        },
        {
          name: "DataExportJob",
          queue_name: "default",
          base_duration: 1200,
          variance: 500,
          error_rate: 0.03,
          runs_per_day: 12
        },
        {
          name: "ImageProcessingJob",
          queue_name: "media",
          base_duration: 500,
          variance: 200,
          error_rate: 0.02,
          runs_per_day: 35
        },
        {
          name: "ReportGeneratorJob",
          queue_name: "reports",
          base_duration: 3000,
          variance: 1200,
          error_rate: 0.03,
          runs_per_day: 8
        },
        {
          name: "CacheWarmingJob",
          queue_name: "default",
          base_duration: 250,
          variance: 80,
          error_rate: 0.005,
          runs_per_day: 100
        },
        {
          name: "CleanupJob",
          queue_name: "maintenance",
          base_duration: 800,
          variance: 300,
          error_rate: 0.01,
          runs_per_day: 4
        },
        {
          name: "NotificationJob",
          queue_name: "notifications",
          base_duration: 100,
          variance: 50,
          error_rate: 0.02,
          runs_per_day: 80
        },
        {
          name: "AnalyticsJob",
          queue_name: "analytics",
          base_duration: 2000,
          variance: 700,
          error_rate: 0.02,
          runs_per_day: 6
        },
        {
          name: "WebhookDeliveryJob",
          queue_name: "webhooks",
          base_duration: 180,
          variance: 100,
          error_rate: 0.05,
          runs_per_day: 45
        },
        {
          name: "ImportJob",
          queue_name: "imports",
          base_duration: 4000,
          variance: 1500,
          error_rate: 0.04,
          runs_per_day: 3
        }
      ].freeze

      def self.seed!(queries)
        print "Generating background jobs"

        jobs = create_jobs
        job_runs_count = create_job_runs(jobs, queries)

        puts "\nCreated #{jobs.count} job classes with #{job_runs_count} runs"
        jobs
      end

      private

      def self.create_jobs
        JOB_DEFINITIONS.map do |job_def|
          ::RailsPulse::Job.create!(
            name: job_def[:name],
            queue_name: job_def[:queue_name]
          )
        end
      end

      def self.create_job_runs(jobs, queries)
        total_days = 7
        job_runs_count = 0

        JOB_DEFINITIONS.each_with_index do |job_def, index|
          job = jobs[index]

          total_days.times do |day_offset|
            day_start = (total_days + 7 - day_offset).days.ago.beginning_of_day
            runs_for_day = [ (job_def[:runs_per_day] * 0.2).to_i + rand(-2..2), 1 ].max

            runs_for_day.times do
              occurred_at = day_start + rand(0..86400).seconds
              duration = job_def[:base_duration] + rand(-job_def[:variance]..job_def[:variance])
              duration = [ duration, 10 ].max

              status, attempts, error_class, error_message = determine_job_status(job_def)
              enqueued_at = occurred_at - rand(1..30).seconds

              job_run = ::RailsPulse::JobRun.create!(
                job: job,
                run_id: SecureRandom.uuid,
                status: status,
                duration: duration,
                occurred_at: occurred_at,
                enqueued_at: enqueued_at,
                attempts: attempts,
                adapter: [ "active_job", "sidekiq", "solid_queue" ].sample,
                error_class: error_class,
                error_message: error_message
              )

              create_job_operations(job_run, job_def, queries, occurred_at)
              job_runs_count += 1
            end

            print "." if day_offset % 3 == 0
          end
        end

        job_runs_count
      end

      def self.determine_job_status(job_def)
        rand_val = rand
        status = if rand_val < job_def[:error_rate]
                  [ "failed", "discarded" ].sample
        elsif rand_val < job_def[:error_rate] + 0.03
                  "retried"
        else
                  "success"
        end

        attempts = case status
        when "success"    then 1
        when "retried"    then rand(2..3)
        when "failed"     then rand(1..3)
        when "discarded"  then rand(3..5)
        else 1
        end

        error_class = error_message = nil
        if [ "failed", "discarded" ].include?(status)
          errors = {
            "ActiveRecord::RecordInvalid" => "Validation failed: Email can't be blank",
            "Net::ReadTimeout" => "Connection timeout after 30 seconds",
            "StandardError" => "Unable to process request",
            "ArgumentError" => "Invalid argument provided",
            "ActiveJob::DeserializationError" => "Failed to deserialize job arguments",
            "JSON::ParserError" => "Unexpected token in JSON",
            "Redis::ConnectionError" => "Connection refused - unable to connect to Redis"
          }
          error_class, error_message = errors.to_a.sample
        end

        [ status, attempts, error_class, error_message ]
      end

      def self.create_job_operations(job_run, job_def, queries, occurred_at)
        operation_count = case job_def[:name]
        when "UserMailerJob", "NotificationJob" then rand(1..3)
        when "DataExportJob", "ReportGeneratorJob", "AnalyticsJob", "ImportJob" then rand(3..8)
        when "ImageProcessingJob" then rand(2..5)
        when "CacheWarmingJob" then rand(2..4)
        when "WebhookDeliveryJob" then rand(1..3)
        when "CleanupJob" then rand(2..5)
        else rand(1..3)
        end

        current_time = 0.0
        operation_count.times do
          operation_type = [ "sql", "sql", "sql", "http", "job", "cache_read", "mailer" ].sample
          operation_duration = case operation_type
          when "sql"        then rand(2..50)
          when "http"       then rand(20..200)
          when "job"        then rand(10..80)
          when "mailer"     then rand(10..80)
          when "cache_read" then rand(1..10)
          else rand(5..50)
          end

          query = (operation_type == "sql" && queries.any?) ? queries.sample : nil
          label = job_operation_label(operation_type, query)
          location = job_codebase_location(job_def)

          ::RailsPulse::Operation.create!(
            job_run: job_run,
            query: query,
            operation_type: operation_type,
            label: label,
            duration: operation_duration,
            codebase_location: location,
            start_time: current_time,
            occurred_at: occurred_at
          )

          current_time += operation_duration
        end
      end

      def self.job_operation_label(operation_type, query)
        case operation_type
        when "sql"
          query&.normalized_sql&.split(" ")&.first(5)&.join(" ") || "SQL Query"
        when "http"
          [ "GET https://api.example.com/notify", "POST https://api.stripe.com/charges", "GET https://s3.amazonaws.com/bucket" ].sample
        when "job"
          [ "SubJob#perform", "ApplicationJob#perform", "Enqueue child job" ].sample
        when "mailer"
          [ "UserMailer#welcome_email", "NotificationMailer#notify", "ReportMailer#send_report" ].sample
        when "cache_read"
          [ "Rails.cache.read(:user_data)", "Rails.cache.fetch(:report_data)", "Rails.cache.read(:session)" ].sample
        else
          "#{operation_type.capitalize} operation"
        end
      end

      def self.job_codebase_location(job_def)
        locations = {
          "UserMailerJob" => "app/mailers/user_mailer.rb",
          "DataExportJob" => "app/jobs/data_export_job.rb",
          "ImageProcessingJob" => "app/jobs/image_processing_job.rb",
          "ReportGeneratorJob" => "app/jobs/report_generator_job.rb",
          "CacheWarmingJob" => "app/jobs/cache_warming_job.rb",
          "CleanupJob" => "app/jobs/cleanup_job.rb",
          "NotificationJob" => "app/jobs/notification_job.rb",
          "AnalyticsJob" => "app/jobs/analytics_job.rb",
          "WebhookDeliveryJob" => "app/jobs/webhook_delivery_job.rb",
          "ImportJob" => "app/jobs/import_job.rb"
        }
        file = locations[job_def[:name]] || "app/jobs/application_job.rb"
        "#{file}:#{rand(10..120)}"
      end
    end
  end
end
