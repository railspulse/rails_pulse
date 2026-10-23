module RailsPulse
  class SummaryJob < ApplicationJob
    # Performs periodic summary aggregation (hourly/daily/weekly/monthly)
    # @param target_hour [Time, nil] The hour to summarize (defaults to 1 hour ago)
    # @return [nil]
    def perform(target_hour = nil)
      target_hour ||= 1.hour.ago.beginning_of_hour

      # Rollup buckets flush on their own clock, so make this process's
      # folded traffic visible before the hour is read. Other processes'
      # buckets are healed by resummarize_hours_with_late_rollups next run.
      Tracker.flush_rollups!

      # Always run hourly summary
      process_hourly_summary(target_hour)

      resummarize_hours_with_late_rollups(target_hour)

      # Check if we should run daily summary (at the start of a new day)
      if midnight?(target_hour)
        process_daily_summary(target_hour.to_date - 1.day)

        # Check if we should run weekly summary (Monday at midnight)
        process_weekly_summary((target_hour.to_date - 1.week).beginning_of_week) if monday?(target_hour)

        # Check if we should run monthly summary (first day of month)
        process_monthly_summary((target_hour.to_date - 1.month).beginning_of_month) if first_of_month?(target_hour)
      end

      enqueue_cloud_sync
    rescue StandardError => e
      log_error(e)
      raise
    end

    # A bucket stops accepting folds STALE_HOUR_GRACE past its hour and is
    # flushed within FLUSH_INTERVAL, so nothing lands later than this after
    # the hour it counts.
    LATE_ROLLUP_LOOKBACK = 3.hours

    private

    # Rollups flush about once a minute per process, and a long request that
    # started in an hour folds only after it finishes, so rows for an hour can
    # land after that hour was summarized — summaries would otherwise
    # permanently undercount each hour's folded tail. A recent hour whose
    # summary no longer matches its raw request count plus its folded route
    # counts is summarized again; the upsert makes that idempotent. Counts are
    # compared rather than timestamps because the summary's updated_at is
    # written by the database and rollup timestamps by Ruby, which clock skew
    # can order either way. Runs before the daily rollup so a corrected hour
    # feeds its day. Healing is best-effort: a failure here must not stop the
    # current hour's summaries or the period rollups.
    def resummarize_hours_with_late_rollups(target_hour)
      return unless RailsPulse::Rollup.table_available?

      window = (target_hour - LATE_ROLLUP_LOOKBACK)...target_hour
      hours = RailsPulse::Rollup.where(period_start: window).distinct.pluck(:period_start)

      hours.each do |hour|
        summarized_count = RailsPulse::Summary.overall_requests
          .where(period_type: "hour", period_start: hour).pick(:count)
        next unless summarized_count

        current_count = RailsPulse::Request.where(occurred_at: hour...(hour + 1.hour)).count +
          RailsPulse::Rollup.where(rollupable_type: "RailsPulse::Route", period_start: hour).sum(:count)
        next if current_count == summarized_count

        RailsPulse.logger.info "Re-summarizing hour #{hour}: rollups or requests landed after its summary"
        SummaryService.new("hour", hour).perform
      end
    rescue StandardError => e
      RailsPulse.logger.error "Could not re-summarize hours with late rollups: #{e.class} - #{e.message}"
    end

    # Cloud receives an hour only once it is summarized, so the sync follows
    # this job rather than running on a schedule of its own. A queue that
    # refuses the job must not fail the summaries already written.
    def enqueue_cloud_sync
      return unless RailsPulse.configuration.cloud.enabled?

      CloudSyncJob.perform_later
    rescue StandardError => e
      RailsPulse.logger.error "Could not enqueue the Rails Pulse Cloud sync: #{e.class} - #{e.message}"
    end

    def midnight?(time)
      time.hour == 0
    end

    def monday?(time)
      time.wday == 1
    end

    def first_of_month?(time)
      time.day == 1
    end

    def process_hourly_summary(hour)
      RailsPulse.logger.info "Processing hourly summary for #{hour}"
      SummaryService.new("hour", hour).perform
    end

    def process_daily_summary(date)
      RailsPulse.logger.info "Processing daily summary for #{date}"
      SummaryService.new("day", date).perform
    end

    def process_weekly_summary(week_start)
      RailsPulse.logger.info "Processing weekly summary for week starting #{week_start}"
      SummaryService.new("week", week_start).perform
    end

    def process_monthly_summary(month_start)
      RailsPulse.logger.info "Processing monthly summary for month starting #{month_start}"
      SummaryService.new("month", month_start).perform
    end

    def log_error(error)
      RailsPulse.logger.error "Summary job failed: #{error.message}"
      RailsPulse.logger.error error.backtrace.join("\n")
    end
  end
end
