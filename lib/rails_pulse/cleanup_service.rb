module RailsPulse
  class CleanupService
    def self.perform
      new.perform
    end

    def initialize
      @config = RailsPulse.configuration
      @stats = {
        time_based: {},
        count_based: {},
        total_deleted: 0
      }
    end

    def perform
      return unless cleanup_enabled?

      RailsPulse.logger.info "Starting data cleanup..."

      perform_time_based_cleanup
      perform_count_based_cleanup
      perform_summary_cleanup

      log_cleanup_summary
      @stats
    end

    private

    def cleanup_enabled?
      @config.archiving_enabled
    end

    def perform_time_based_cleanup
      return unless @config.full_retention_period

      # Enforce a 1-hour minimum so records always have time to be summarized
      # before deletion, regardless of how short full_retention_period is set.
      cutoff_time = [ @config.full_retention_period.ago, 1.hour.ago ].min
      RailsPulse.logger.info "Time-based cleanup: removing records older than #{cutoff_time}"

      # Clean up in order that respects foreign key constraints
      @stats[:time_based][:operations]            = cleanup_operations_by_time(cutoff_time)
      @stats[:time_based][:job_runs]              = cleanup_job_runs_by_time(cutoff_time)
      @stats[:time_based][:requests]              = cleanup_requests_by_time(cutoff_time)
      @stats[:time_based][:queries]               = cleanup_queries_by_time(cutoff_time)
      @stats[:time_based][:routes]                = cleanup_routes_by_time(cutoff_time)
      @stats[:time_based][:jobs]                  = cleanup_jobs_by_time(cutoff_time)
      @stats[:time_based][:exception_occurrences] = cleanup_exception_occurrences_by_time(cutoff_time)
      @stats[:time_based][:exception_groups]      = cleanup_orphaned_exception_groups
    end

    def perform_count_based_cleanup
      return unless @config.max_table_records&.any?

      RailsPulse.logger.info "Count-based cleanup: enforcing table record limits"

      # Only delete records from periods that have already been summarized.
      # This prevents count-based cleanup from removing data before the summary
      # job has had a chance to aggregate it.
      cutoff = summarized_cutoff

      # Operations: only delete those before the summarization cutoff
      ops_scope = cutoff ? RailsPulse::Operation.where("occurred_at < ?", cutoff) : RailsPulse::Operation.none

      # Clean up in order that respects foreign key constraints
      @stats[:count_based][:operations]            = cleanup_by_count(RailsPulse::Operation, :rails_pulse_operations, order_column: :occurred_at, scope: ops_scope)
      @stats[:count_based][:job_runs]              = cleanup_job_runs_by_count
      @stats[:count_based][:requests]              = cleanup_requests_by_count
      @stats[:count_based][:queries]               = cleanup_queries_by_count
      @stats[:count_based][:routes]                = cleanup_routes_by_count
      @stats[:count_based][:jobs]                  = cleanup_jobs_by_count
      @stats[:count_based][:exception_occurrences] = cleanup_exception_occurrences_by_count
      @stats[:count_based][:exception_groups]      = cleanup_orphaned_exception_groups
    end

    # Shared helper: delete oldest records beyond a configured max count
    def cleanup_by_count(model_class, table_key, order_column:, scope: nil)
      max_records = @config.max_table_records[table_key]
      return 0 unless max_records

      relation = scope || model_class
      current_count = relation.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = relation.order(order_column => :asc).limit(records_to_delete).pluck(:id)
      model_class.where(id: ids_to_delete).delete_all
      records_to_delete
    end

    # Time-based cleanup methods

    def cleanup_operations_by_time(cutoff_time)
      RailsPulse::Operation.where("occurred_at < ?", cutoff_time).delete_all
    end

    def cleanup_requests_by_time(cutoff_time)
      request_subquery = RailsPulse::Request.where("occurred_at < ?", cutoff_time).select(:id)
      RailsPulse::Operation.where(request_id: request_subquery).delete_all
      RailsPulse::Request.where("occurred_at < ?", cutoff_time).delete_all
    end

    def cleanup_queries_by_time(cutoff_time)
      RailsPulse::Query
        .where("created_at < ?", cutoff_time)
        .where("id NOT IN (SELECT query_id FROM rails_pulse_operations WHERE query_id IS NOT NULL)")
        .delete_all
    end

    def cleanup_routes_by_time(cutoff_time)
      RailsPulse::Route
        .where("created_at < ?", cutoff_time)
        .where("id NOT IN (SELECT route_id FROM rails_pulse_requests WHERE route_id IS NOT NULL)")
        .delete_all
    end

    def cleanup_job_runs_by_time(cutoff_time)
      job_run_subquery = RailsPulse::JobRun.where("occurred_at < ?", cutoff_time).select(:id)
      RailsPulse::Operation.where(job_run_id: job_run_subquery).delete_all
      RailsPulse::JobRun.where("occurred_at < ?", cutoff_time).delete_all
    end

    def cleanup_jobs_by_time(cutoff_time)
      RailsPulse::Job
        .where("created_at < ?", cutoff_time)
        .where("id NOT IN (SELECT job_id FROM rails_pulse_job_runs WHERE job_id IS NOT NULL)")
        .delete_all
    end

    # Count-based cleanup methods (complex cases that need custom scoping)

    def cleanup_requests_by_count
      max_records = @config.max_table_records[:rails_pulse_requests]
      return 0 unless max_records

      # Only delete requests from periods that have already been summarized
      cutoff = summarized_cutoff
      return 0 unless cutoff

      current_count = RailsPulse::Request.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = RailsPulse::Request
        .where("occurred_at < ?", cutoff)
        .order(occurred_at: :asc)
        .limit(records_to_delete)
        .pluck(:id)
      return 0 if ids_to_delete.empty?

      RailsPulse::Operation.where(request_id: ids_to_delete).delete_all
      RailsPulse::Request.where(id: ids_to_delete).delete_all
      ids_to_delete.size
    end

    def cleanup_job_runs_by_count
      max_records = @config.max_table_records[:rails_pulse_job_runs]
      return 0 unless max_records

      current_count = RailsPulse::JobRun.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = RailsPulse::JobRun.order(occurred_at: :asc).limit(records_to_delete).pluck(:id)
      return 0 if ids_to_delete.empty?

      RailsPulse::Operation.where(job_run_id: ids_to_delete).delete_all
      RailsPulse::JobRun.where(id: ids_to_delete).delete_all
      ids_to_delete.size
    end

    def cleanup_queries_by_count
      scope = RailsPulse::Query.where(
        "id NOT IN (SELECT query_id FROM rails_pulse_operations WHERE query_id IS NOT NULL)"
      )
      cleanup_by_count(RailsPulse::Query, :rails_pulse_queries, order_column: :created_at, scope: scope)
    end

    def cleanup_routes_by_count
      scope = RailsPulse::Route.where(
        "id NOT IN (SELECT route_id FROM rails_pulse_requests WHERE route_id IS NOT NULL)"
      )
      cleanup_by_count(RailsPulse::Route, :rails_pulse_routes, order_column: :created_at, scope: scope)
    end

    def cleanup_jobs_by_count
      scope = RailsPulse::Job.where(
        "id NOT IN (SELECT job_id FROM rails_pulse_job_runs WHERE job_id IS NOT NULL)"
      )
      cleanup_by_count(RailsPulse::Job, :rails_pulse_jobs, order_column: :created_at, scope: scope)
    end

    def cleanup_exception_occurrences_by_time(cutoff_time)
      RailsPulse::ExceptionOccurrence.where("occurred_at < ?", cutoff_time).delete_all
    end

    def cleanup_exception_occurrences_by_count
      cleanup_by_count(RailsPulse::ExceptionOccurrence, :rails_pulse_exception_occurrences, order_column: :occurred_at)
    end

    # Delete groups whose last occurrence was removed — uses an atomic subquery
    # so no orphan can be deleted while a concurrent occurrence is being inserted.
    def cleanup_orphaned_exception_groups
      RailsPulse::ExceptionGroup
        .where("id NOT IN (SELECT DISTINCT exception_group_id FROM rails_pulse_exception_occurrences)")
        .delete_all
    end

    def perform_summary_cleanup
      # Hourly summaries are only used for the 1-day time range view — anything
      # older than 2 days is unreachable in the UI and safe to delete.
      cutoff = 2.days.ago
      deleted = RailsPulse::Summary.where(period_type: "hour").where("period_start < ?", cutoff).delete_all
      @stats[:time_based][:hourly_summaries] = deleted
    end

    # Returns the period_end of the most recent completed hourly overall-request
    # summary, or nil if the summary job has never run. Records with occurred_at
    # before this timestamp have been fully aggregated and are safe to delete.
    def summarized_cutoff
      @summarized_cutoff ||= RailsPulse::Summary
        .where(summarizable_type: "RailsPulse::Request", summarizable_id: 0, period_type: "hour")
        .maximum(:period_end)
    end

    def log_cleanup_summary
      total_time_based = @stats[:time_based].values.sum
      total_count_based = @stats[:count_based].values.sum
      @stats[:total_deleted] = total_time_based + total_count_based

      RailsPulse.logger.info "Cleanup completed:"
      RailsPulse.logger.info "  Time-based: #{total_time_based} records deleted"
      RailsPulse.logger.info "  Count-based: #{total_count_based} records deleted"
      RailsPulse.logger.info "  Total: #{@stats[:total_deleted]} records deleted"

      if @stats[:total_deleted] > 0
        RailsPulse.logger.info "  Breakdown:"
        @stats[:time_based].each do |table, count|
          RailsPulse.logger.info "    #{table} (time): #{count}" if count > 0
        end
        @stats[:count_based].each do |table, count|
          RailsPulse.logger.info "    #{table} (count): #{count}" if count > 0
        end
      end
    end
  end
end
