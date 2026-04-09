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

      log_cleanup_summary
      @stats
    end

    private

    def cleanup_enabled?
      @config.archiving_enabled
    end

    def perform_time_based_cleanup
      return unless @config.full_retention_period

      cutoff_time = @config.full_retention_period.ago
      RailsPulse.logger.info "Time-based cleanup: removing records older than #{cutoff_time}"

      # Clean up in order that respects foreign key constraints
      @stats[:time_based][:operations] = cleanup_operations_by_time(cutoff_time)
      @stats[:time_based][:job_runs]   = cleanup_job_runs_by_time(cutoff_time)
      @stats[:time_based][:requests]   = cleanup_requests_by_time(cutoff_time)
      @stats[:time_based][:queries]    = cleanup_queries_by_time(cutoff_time)
      @stats[:time_based][:routes]     = cleanup_routes_by_time(cutoff_time)
      @stats[:time_based][:jobs]       = cleanup_jobs_by_time(cutoff_time)
    end

    def perform_count_based_cleanup
      return unless @config.max_table_records&.any?

      RailsPulse.logger.info "Count-based cleanup: enforcing table record limits"

      # Clean up in order that respects foreign key constraints
      @stats[:count_based][:operations] = cleanup_by_count(RailsPulse::Operation, :rails_pulse_operations, order_column: :occurred_at)
      @stats[:count_based][:job_runs]   = cleanup_by_count(RailsPulse::JobRun, :rails_pulse_job_runs, order_column: :occurred_at)
      @stats[:count_based][:requests]   = cleanup_requests_by_count
      @stats[:count_based][:queries]    = cleanup_queries_by_count
      @stats[:count_based][:routes]     = cleanup_routes_by_count
      @stats[:count_based][:jobs]       = cleanup_jobs_by_count
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
      request_ids = RailsPulse::Request.where("occurred_at < ?", cutoff_time).pluck(:id)
      RailsPulse::Operation.where(request_id: request_ids).delete_all
      RailsPulse::Request.where(id: request_ids).delete_all
      request_ids.size
    end

    def cleanup_queries_by_time(cutoff_time)
      query_ids_with_operations = RailsPulse::Operation.distinct.pluck(:query_id).compact
      RailsPulse::Query
        .where("created_at < ?", cutoff_time)
        .where.not(id: query_ids_with_operations)
        .delete_all
    end

    def cleanup_routes_by_time(cutoff_time)
      route_ids_with_requests = RailsPulse::Request.distinct.pluck(:route_id).compact
      RailsPulse::Route
        .where("created_at < ?", cutoff_time)
        .where.not(id: route_ids_with_requests)
        .delete_all
    end

    def cleanup_job_runs_by_time(cutoff_time)
      RailsPulse::JobRun.where("occurred_at < ?", cutoff_time).delete_all
    end

    def cleanup_jobs_by_time(cutoff_time)
      job_ids_with_runs = RailsPulse::JobRun.distinct.pluck(:job_id).compact
      RailsPulse::Job
        .where("created_at < ?", cutoff_time)
        .where.not(id: job_ids_with_runs)
        .delete_all
    end

    # Count-based cleanup methods (complex cases that need custom scoping)

    def cleanup_requests_by_count
      max_records = @config.max_table_records[:rails_pulse_requests]
      return 0 unless max_records

      current_count = RailsPulse::Request.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = RailsPulse::Request.order(occurred_at: :asc).limit(records_to_delete).pluck(:id)
      RailsPulse::Operation.where(request_id: ids_to_delete).delete_all
      RailsPulse::Request.where(id: ids_to_delete).delete_all
      records_to_delete
    end

    def cleanup_queries_by_count
      query_ids_with_operations = RailsPulse::Operation.distinct.pluck(:query_id).compact
      scope = RailsPulse::Query.where.not(id: query_ids_with_operations)
      cleanup_by_count(RailsPulse::Query, :rails_pulse_queries, order_column: :created_at, scope: scope)
    end

    def cleanup_routes_by_count
      route_ids_with_requests = RailsPulse::Request.distinct.pluck(:route_id).compact
      scope = RailsPulse::Route.where.not(id: route_ids_with_requests)
      cleanup_by_count(RailsPulse::Route, :rails_pulse_routes, order_column: :created_at, scope: scope)
    end

    def cleanup_jobs_by_count
      job_ids_with_runs = RailsPulse::JobRun.distinct.pluck(:job_id).compact
      scope = RailsPulse::Job.where.not(id: job_ids_with_runs)
      cleanup_by_count(RailsPulse::Job, :rails_pulse_jobs, order_column: :created_at, scope: scope)
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
