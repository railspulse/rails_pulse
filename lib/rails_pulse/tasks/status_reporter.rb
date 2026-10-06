# frozen_string_literal: true

module RailsPulse
  module Tasks
    # `rails rails_pulse:status` — where does this install stand?
    #
    # Answers, from the shell and without opening the dashboard, the questions
    # an upgrade tends to leave hanging: is the schema current for this gem,
    # are there migration files that have not been run, has the route backfill
    # been done, does the initializer mention the settings this version added.
    # Anything that needs action is repeated in a closing "Action needed"
    # list, and `report` returns false in that case so release scripts can
    # stop on it.
    #
    # Below that, "Suggestions" covers how the install is run rather than
    # whether it is current: SummaryJob or CleanupJob not running, hourly
    # summaries kept too briefly, jobs not tracked. Development and test
    # environments rarely schedule either job, so these never change the
    # exit status.
    class StatusReporter
      # Hourly summaries back deployment comparisons and hour-precise change
      # points; below a week, last week's deploys can no longer be compared.
      RECOMMENDED_HOURLY_RETENTION = 7.days

      # CleanupJob is meant to run daily.
      CLEANUP_STALE_AFTER = 2.days

      attr_reader :output, :config

      def self.report(output: $stdout)
        new(output: output).report
      end

      def initialize(output: $stdout)
        @output = output
        @config = RailsPulse.configuration
        @actions = []
        @suggestions = []
      end

      # Returns true when nothing needs attention.
      def report
        output.puts "Rails Pulse #{RailsPulse::VERSION}"
        output.puts

        print_database
        print_schema
        print_migrations
        print_route_backfill
        print_initializer
        print_tracking
        print_writer
        print_summaries
        print_retention
        print_cleanup
        print_jobs
        print_cloud
        print_actions
        print_suggestions

        @actions.empty?
      end

      private

      def action(text)
        @actions << text
      end

      def suggest(text)
        @suggestions << text
      end

      # -- sections -----------------------------------------------------------

      def print_database
        connection = RailsPulse::ApplicationRecord.connection
        name = RailsPulse::ApplicationRecord.connection_db_config.name
        separate = config.connects_to.present?
        output.puts "Database:   #{connection.adapter_name} (#{name}#{separate ? ", separate Pulse database" : ""})"
      rescue StandardError => e
        output.puts "Database:   unavailable (#{e.class}: #{e.message})"
        action "Database connection failed; nothing below could be checked."
      end

      def print_schema
        RailsPulse::SchemaCheck.reset!
        missing = RailsPulse::SchemaCheck.missing

        if missing.empty?
          output.puts "Schema:     up to date for #{RailsPulse::VERSION}"
          return
        end

        output.puts "Schema:     BEHIND this gem version"
        missing.each do |table, columns|
          output.puts(columns == [ :table ] ? "              #{table}: table missing" : "              #{table}: missing #{columns.join(', ')}")
        end
        action "Schema is behind the gem. Run: #{upgrade_commands.join(' && ')}"
      end

      def print_migrations
        not_copied = gem_migrations_not_in_host
        pending = pending_migrations

        if not_copied.empty? && pending.empty?
          output.puts "Migrations: none pending"
          return
        end

        if not_copied.any?
          output.puts "Migrations: #{not_copied.size} gem migration(s) not yet copied into this app:"
          not_copied.each { |name| output.puts "              #{name}" }
          action "Copy this version's migrations: rails generate rails_pulse:upgrade"
        end

        if pending.any?
          output.puts "Migrations: #{pending.size} migration file(s) present but not run:"
          pending.each { |name| output.puts "              #{name}" }
          action "Run pending migrations: #{migrate_command}"
        end
      end

      def print_route_backfill
        unless RailsPulse::SchemaCheck.current?
          output.puts "Routes:     (skipped — schema is behind)"
          return
        end

        backfill = RailsPulse::Route.needs_action_backfill?
        index = RailsPulse::RouteIndexes.exists?(RailsPulse::ApplicationRecord.connection)

        if !backfill && index
          output.puts "Routes:     actions backfilled, unrecognised-path index present"
          return
        end

        output.puts "Routes:     #{backfill ? 'actions NOT backfilled' : 'actions backfilled'}, " \
                    "unrecognised-path index #{index ? 'present' : 'MISSING'}"
        action "Backfill route actions and create the unrecognised-path index: rails rails_pulse:migrate_routes"
      rescue StandardError => e
        output.puts "Routes:     could not check (#{e.class}: #{e.message})"
      end

      def print_initializer
        path = Rails.root.join("config", "initializers", "rails_pulse.rb")
        unless path.exist?
          output.puts "Initializer: config/initializers/rails_pulse.rb not found"
          action "Create the initializer: rails generate rails_pulse:install"
          return
        end

        missing = RailsPulse::Installers::ConfigUpdater.missing(destination: path.to_s)
        keys = missing[:keys] + missing[:hash_keys]
        if keys.empty?
          output.puts "Initializer: mentions every setting this version knows"
          return
        end

        output.puts "Initializer: #{keys.size} setting(s) from this version not mentioned: #{keys.join(', ')}"
        action "Append the new settings to the initializer: rails generate rails_pulse:upgrade (review with git diff)"
      end

      def print_tracking
        auth = if !config.authentication_enabled
          "disabled"
        elsif config.authentication_method || config.authorize
          "custom hook"
        else
          "HTTP Basic (RAILS_PULSE_PASSWORD #{ENV["RAILS_PULSE_PASSWORD"].to_s.empty? ? 'NOT set' : 'set'})"
        end

        output.puts "Tracking:   enabled=#{config.enabled} requests=#{config.enabled} jobs=#{config.track_jobs} " \
                    "exceptions=#{config.track_exceptions} async=#{config.async}"
        output.puts "Dashboard:  mount_dashboard=#{config.mount_dashboard} authentication=#{auth}"
        output.puts "API:        api_token #{config.api_token.to_s.empty? ? 'NOT set (rails-pulse CLI and MCP server refuse every request)' : 'set'}, " \
                    "deployment_token #{config.deployment_token.to_s.empty? ? 'NOT set (POST deployments refuses every request; the rake tasks still work)' : 'set'}"
      end

      # This process has no writer of its own; read every process's heartbeats
      def print_writer
        unless RailsPulse::Event.table_available?
          output.puts "Writer:     (skipped — events table missing, schema is behind)"
          return
        end

        summary = RailsPulse::WriterHeartbeat.summary
        if summary[:last_sampled_at].nil?
          output.puts "Writer:     no heartbeats yet (they start when a process with config.async tracks its first request)"
          return
        end

        dropped = summary[:dropped].to_i
        output.puts "Writer:     #{summary[:processes]} live process(es), queue depth #{summary[:queue_depth]}/#{summary[:queue_size]}, " \
                    "#{dropped} request(s) dropped in the last hour, last heartbeat #{time_ago(summary[:last_sampled_at])}"
        return if dropped.zero?

        action "The writer dropped #{dropped} request(s) in the last hour. Raise config.async_queue_size or check database latency."
      rescue StandardError => e
        output.puts "Writer:     could not check (#{e.class}: #{e.message})"
      end

      def print_summaries
        last = RailsPulse::Summary.maximum(:updated_at)
        if last.nil?
          output.puts "Summaries:  none generated yet (schedule RailsPulse::SummaryJob hourly; backfill with rails rails_pulse:backfill_summaries)"
          suggest "Schedule RailsPulse::SummaryJob hourly (see the README); the dashboard, the API and cleanup all read its summaries."
        elsif last < 2.hours.ago
          output.puts "Summaries:  last generated #{time_ago(last)} — stale (is RailsPulse::SummaryJob scheduled?)"
          suggest "RailsPulse::SummaryJob last ran #{time_ago(last)}; check it is scheduled hourly and the worker is running."
        else
          output.puts "Summaries:  last generated #{time_ago(last)}"
        end
        print_hourly_coverage
      rescue StandardError => e
        output.puts "Summaries:  could not check (#{e.class}: #{e.message})"
      end

      # Hours SummaryJob skipped inside the hourly retention window. It writes
      # the overall request row for every hour, even an empty one, so a gap
      # between the oldest and newest row is an hour it did not run.
      def print_hourly_coverage
        hours = RailsPulse::Summary.overall_requests
          .where(period_type: "hour")
          .where(period_start: config.hourly_summary_retention.ago..)
          .distinct
          .pluck(:period_start)
        return if hours.empty?

        span = ((hours.max - hours.min) / 1.hour).round + 1
        missing = span - hours.size
        if missing.zero?
          output.puts "            hourly: #{hours.size} consecutive hour(s) summarized"
        else
          output.puts "            hourly: #{hours.size} of the last #{span} hours summarized, #{missing} missing"
          suggest "RailsPulse::SummaryJob skipped #{missing} hour(s) in the last #{span}. Check its schedule; " \
                  "rails rails_pulse:backfill_summaries fills the gaps."
        end
      end

      def print_retention
        hourly = config.hourly_summary_retention
        raw = config.full_retention_period ? days(config.full_retention_period) : "no age limit"
        output.puts "Retention:  raw data #{raw}, hourly summaries #{days(hourly)}"
        return if hourly >= RECOMMENDED_HOURLY_RETENTION

        suggest "Keep hourly summaries for #{days(RECOMMENDED_HOURLY_RETENTION)}: deployment comparisons and hour-precise " \
                "change points read them, and at #{days(hourly)} a deploy from last week can no longer be compared. " \
                "Add config.hourly_summary_retention = #{RECOMMENDED_HOURLY_RETENTION.in_days.to_i}.days to config/initializers/rails_pulse.rb."
      end

      def print_cleanup
        unless config.archiving_enabled
          output.puts "Cleanup:    off (config.archiving_enabled = false); nothing is pruned"
          return
        end
        unless RailsPulse::Event.table_available?
          output.puts "Cleanup:    (skipped — events table missing, schema is behind)"
          return
        end

        run = RailsPulse::CleanupRun.latest
        if run.nil?
          print_cleanup_never_run
        elsif run.outcome == "failed"
          stages = run.metadata_hash["failed_stages"].to_a.join(", ")
          output.puts "Cleanup:    last ran #{time_ago(run.occurred_at)} and failed (#{stages})"
          suggest "The last cleanup failed in #{stages}; the log has the error. Run rails rails_pulse:cleanup to retry."
        elsif run.occurred_at < CLEANUP_STALE_AFTER.ago
          output.puts "Cleanup:    last ran #{time_ago(run.occurred_at)} — stale (is RailsPulse::CleanupJob scheduled?)"
          suggest "Cleanup last ran #{time_ago(run.occurred_at)}; schedule RailsPulse::CleanupJob daily so retention is enforced."
        else
          output.puts "Cleanup:    last ran #{time_ago(run.occurred_at)}, #{run.value.to_i} row(s) deleted"
        end
      rescue StandardError => e
        output.puts "Cleanup:    could not check (#{e.class}: #{e.message})"
      end

      # No run recorded is only a problem once there is something to prune.
      def print_cleanup_never_run
        overdue = config.full_retention_period &&
          RailsPulse::Request.where(occurred_at: ...(config.full_retention_period + 1.day).ago).exists?

        if overdue
          output.puts "Cleanup:    no run recorded, and requests older than #{days(config.full_retention_period)} are still held"
          suggest "Schedule RailsPulse::CleanupJob daily (see the README); data past retention is not being pruned."
        else
          output.puts "Cleanup:    no run recorded yet (schedule RailsPulse::CleanupJob daily)"
        end
      end

      def print_jobs
        unless config.track_jobs
          output.puts "Jobs:       not tracked"
          suggest "Track background jobs to see failures and slow jobs alongside requests: " \
                  "config.track_jobs = true in config/initializers/rails_pulse.rb."
          return
        end

        unless RailsPulse::SchemaCheck.current?
          output.puts "Jobs:       tracked (count skipped — schema is behind)"
          return
        end

        count = RailsPulse::Job.count
        output.puts(count.zero? ? "Jobs:       tracked, none recorded yet" : "Jobs:       tracked, #{count} job class(es) recorded")
      rescue StandardError => e
        output.puts "Jobs:       could not check (#{e.class}: #{e.message})"
      end

      # Reported, never an action: a Cloud outage or a refused key must not
      # fail a deploy that runs this task.
      def print_cloud
        cloud = config.cloud
        unless cloud.enabled?
          output.puts "Cloud:      off (set config.cloud.api_key and config.cloud.application to send to Rails Pulse Cloud)"
          return
        end

        unless RailsPulse::Cloud::Installation.table_exists? && RailsPulse::Cloud::BufferedBatch.table_exists?
          output.puts "Cloud:      (skipped — Cloud tables missing, schema is behind)"
          return
        end

        installation = RailsPulse::Cloud::Installation.existing
        buffered = RailsPulse::Cloud::BufferedBatch.count
        buffer = "#{buffered} batch(es) buffered (#{(RailsPulse::Cloud::BufferedBatch.sum(:byte_size) / 1024.0).round(1)} KB)"
        output.puts "Cloud:      #{cloud.application} (#{cloud.environment}) to #{cloud.url}: #{cloud_state(installation)}; #{buffer}"
        return suggest_cloud_health_job if installation.nil?

        output.puts "            last error #{time_ago(installation.last_error_at)}: #{installation.last_error}" if installation.last_error.present?
        suggest installation.pause_reason if installation.paused?
        if installation.contract_deprecated_on.present?
          suggest "Rails Pulse Cloud stops accepting this gem's sync contract on #{installation.contract_deprecated_on}; upgrade rails_pulse before then."
        end
        suggest_cloud_health_job if installation.last_health_at.nil? || installation.last_health_at < 5.minutes.ago
      rescue StandardError => e
        output.puts "Cloud:      could not check (#{e.class}: #{e.message})"
      end

      def cloud_state(installation)
        return "not synced yet" if installation.nil?
        return "paused until #{installation.paused_until.utc.iso8601}" if installation.paused?
        return "connected, last accepted #{time_ago(installation.last_success_at)}" if installation.last_success_at

        "nothing accepted yet"
      end

      def suggest_cloud_health_job
        suggest "Schedule RailsPulse::CloudHealthJob every minute (see config/initializers/rails_pulse.rb). It sends health " \
                "updates and retries buffered batches; the hourly sync follows RailsPulse::SummaryJob on its own."
      end

      def print_actions
        output.puts
        if @actions.empty?
          output.puts "OK — nothing to do."
        else
          output.puts "Action needed:"
          @actions.each { |text| output.puts "  - #{text}" }
        end
      end

      def print_suggestions
        return if @suggestions.empty?

        output.puts
        output.puts "Suggestions:"
        @suggestions.each { |text| output.puts "  - #{text}" }
      end

      # -- helpers ------------------------------------------------------------

      def gem_migrations_not_in_host
        gem_dir = RailsPulse::Engine.root.join("db", "rails_pulse_migrate")
        return [] unless gem_dir.directory?

        host = %w[db/migrate db/rails_pulse_migrate].flat_map do |dir|
          Dir.glob(Rails.root.join(dir, "*.rb").to_s).map { |f| File.basename(f) }
        end
        Dir.glob(gem_dir.join("*.rb").to_s).map { |f| File.basename(f) }.sort - host
      end

      # Migration files on disk whose version is not recorded on the Pulse
      # connection. Names only; the versions are in the filenames.
      def pending_migrations
        context = RailsPulse::ApplicationRecord.connection_pool.migration_context
        applied = context.get_all_versions
        context.migrations.reject { |m| applied.include?(m.version) }.map { |m| File.basename(m.filename) }
      rescue StandardError
        []
      end

      def upgrade_commands
        [ "rails generate rails_pulse:upgrade", migrate_command, "rails rails_pulse:migrate_routes" ]
      end

      def migrate_command
        config.connects_to.present? ? "rails db:migrate:rails_pulse" : "rails db:migrate"
      end

      def days(duration)
        value = (duration / 1.day.to_f).round(1)
        "#{value == value.to_i ? value.to_i : value} day#{'s' unless value == 1}"
      end

      def time_ago(time)
        seconds = (Time.current - time).to_i
        return "#{seconds}s ago" if seconds < 60
        return "#{seconds / 60}m ago" if seconds < 3600
        return "#{seconds / 3600}h ago" if seconds < 86_400

        "#{seconds / 86_400}d ago"
      end
    end
  end
end
