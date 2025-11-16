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

      Rails.logger.info "[RailsPulse] Starting data cleanup..."

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
      Rails.logger.info "[RailsPulse] Time-based cleanup: removing records older than #{cutoff_time}"

      # Clean up in order that respects foreign key constraints
      @stats[:time_based][:operations] = cleanup_operations_by_time(cutoff_time)
      @stats[:time_based][:job_runs] = cleanup_job_runs_by_time(cutoff_time)
      @stats[:time_based][:requests] = cleanup_requests_by_time(cutoff_time)
      @stats[:time_based][:queries] = cleanup_queries_by_time(cutoff_time)
      @stats[:time_based][:routes] = cleanup_routes_by_time(cutoff_time)
      @stats[:time_based][:jobs] = cleanup_jobs_by_time(cutoff_time)
    end

    def perform_count_based_cleanup
      return unless @config.max_table_records&.any?

      Rails.logger.info "[RailsPulse] Count-based cleanup: enforcing table record limits"

      # Clean up in order that respects foreign key constraints
      @stats[:count_based][:operations] = cleanup_operations_by_count
      @stats[:count_based][:job_runs] = cleanup_job_runs_by_count
      @stats[:count_based][:requests] = cleanup_requests_by_count
      @stats[:count_based][:queries] = cleanup_queries_by_count
      @stats[:count_based][:routes] = cleanup_routes_by_count
      @stats[:count_based][:jobs] = cleanup_jobs_by_count
    end

    # Time-based cleanup methods
    def cleanup_operations_by_time(cutoff_time)
      return 0 unless defined?(RailsPulse::Operation)

      count = RailsPulse::Operation.where("occurred_at < ?", cutoff_time).count
      RailsPulse::Operation.where("occurred_at < ?", cutoff_time).delete_all
      count
    end

    def cleanup_requests_by_time(cutoff_time)
      return 0 unless defined?(RailsPulse::Request)

      count = RailsPulse::Request.where("occurred_at < ?", cutoff_time).count
      request_ids = RailsPulse::Request.where("occurred_at < ?", cutoff_time).pluck(:id)

      # Delete associated operations first to respect foreign key constraints
      RailsPulse::Operation.where(request_id: request_ids).delete_all

      RailsPulse::Request.where("occurred_at < ?", cutoff_time).delete_all
      count
    end

    def cleanup_queries_by_time(cutoff_time)
      return 0 unless defined?(RailsPulse::Query)

      # Only delete queries that have no associated operations
      query_ids_with_operations = RailsPulse::Operation.distinct.pluck(:query_id).compact
      count = RailsPulse::Query
        .where("created_at < ?", cutoff_time)
        .where.not(id: query_ids_with_operations)
        .count
      RailsPulse::Query
        .where("created_at < ?", cutoff_time)
        .where.not(id: query_ids_with_operations)
        .delete_all
      count
    end

    def cleanup_routes_by_time(cutoff_time)
      return 0 unless defined?(RailsPulse::Route)

      # Only delete routes that have no associated requests
      route_ids_with_requests = RailsPulse::Request.distinct.pluck(:route_id).compact
      count = RailsPulse::Route
        .where("created_at < ?", cutoff_time)
        .where.not(id: route_ids_with_requests)
        .count
      RailsPulse::Route
        .where("created_at < ?", cutoff_time)
        .where.not(id: route_ids_with_requests)
        .delete_all
      count
    end

    def cleanup_job_runs_by_time(cutoff_time)
      return 0 unless defined?(RailsPulse::JobRun)

      job_runs = RailsPulse::JobRun.where("occurred_at < ?", cutoff_time)
      count = job_runs.count
      job_runs.delete_all
      count
    end

    def cleanup_jobs_by_time(cutoff_time)
      return 0 unless defined?(RailsPulse::Job)

      job_ids_with_runs = RailsPulse::JobRun.distinct.pluck(:job_id).compact
      jobs = RailsPulse::Job
        .where("created_at < ?", cutoff_time)
        .where.not(id: job_ids_with_runs)
      count = jobs.count
      jobs.delete_all
      count
    end

    # Count-based cleanup methods
    def cleanup_operations_by_count
      return 0 unless defined?(RailsPulse::Operation)

      max_records = @config.max_table_records[:rails_pulse_operations]
      return 0 unless max_records

      current_count = RailsPulse::Operation.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = RailsPulse::Operation
        .order(:occurred_at)
        .limit(records_to_delete)
        .pluck(:id)

      RailsPulse::Operation.where(id: ids_to_delete).delete_all
      records_to_delete
    end

    def cleanup_requests_by_count
      return 0 unless defined?(RailsPulse::Request)

      max_records = @config.max_table_records[:rails_pulse_requests]
      return 0 unless max_records

      current_count = RailsPulse::Request.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = RailsPulse::Request
        .order(:occurred_at)
        .limit(records_to_delete)
        .pluck(:id)

      # Delete associated operations first to respect foreign key constraints
      RailsPulse::Operation.where(request_id: ids_to_delete).delete_all

      RailsPulse::Request.where(id: ids_to_delete).delete_all
      records_to_delete
    end

    def cleanup_queries_by_count
      return 0 unless defined?(RailsPulse::Query)

      max_records = @config.max_table_records[:rails_pulse_queries]
      return 0 unless max_records

      # Only consider queries that have no associated operations
      query_ids_with_operations = RailsPulse::Operation.distinct.pluck(:query_id).compact
      available_queries = RailsPulse::Query.where.not(id: query_ids_with_operations)
      current_count = available_queries.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = available_queries
        .order(:created_at)
        .limit(records_to_delete)
        .pluck(:id)

      RailsPulse::Query.where(id: ids_to_delete).delete_all
      records_to_delete
    end

    def cleanup_routes_by_count
      return 0 unless defined?(RailsPulse::Route)

      max_records = @config.max_table_records[:rails_pulse_routes]
      return 0 unless max_records

      # Only consider routes that have no associated requests
      route_ids_with_requests = RailsPulse::Request.distinct.pluck(:route_id).compact
      available_routes = RailsPulse::Route.where.not(id: route_ids_with_requests)
      current_count = available_routes.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = available_routes
        .order(:created_at)
        .limit(records_to_delete)
        .pluck(:id)

      RailsPulse::Route.where(id: ids_to_delete).delete_all
      records_to_delete
    end

    def cleanup_job_runs_by_count
      return 0 unless defined?(RailsPulse::JobRun)

      max_records = @config.max_table_records[:rails_pulse_job_runs]
      return 0 unless max_records

      current_count = RailsPulse::JobRun.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = RailsPulse::JobRun
        .order(:occurred_at)
        .limit(records_to_delete)
        .pluck(:id)

      RailsPulse::JobRun.where(id: ids_to_delete).delete_all
      records_to_delete
    end

    def cleanup_jobs_by_count
      return 0 unless defined?(RailsPulse::Job)

      max_records = @config.max_table_records[:rails_pulse_jobs]
      return 0 unless max_records

      job_ids_with_runs = RailsPulse::JobRun.distinct.pluck(:job_id).compact
      available_jobs = RailsPulse::Job.where.not(id: job_ids_with_runs)
      current_count = available_jobs.count
      return 0 if current_count <= max_records

      records_to_delete = current_count - max_records
      ids_to_delete = available_jobs
        .order(:created_at)
        .limit(records_to_delete)
        .pluck(:id)

      RailsPulse::Job.where(id: ids_to_delete).delete_all
      records_to_delete
    end

    def log_cleanup_summary
      total_time_based = @stats[:time_based].values.sum
      total_count_based = @stats[:count_based].values.sum
      @stats[:total_deleted] = total_time_based + total_count_based

      Rails.logger.info "[RailsPulse] Cleanup completed:"
      Rails.logger.info "  Time-based: #{total_time_based} records deleted"
      Rails.logger.info "  Count-based: #{total_count_based} records deleted"
      Rails.logger.info "  Total: #{@stats[:total_deleted]} records deleted"

      if @stats[:total_deleted] > 0
        Rails.logger.info "  Breakdown:"
        @stats[:time_based].each do |table, count|
          Rails.logger.info "    #{table} (time): #{count}" if count > 0
        end
        @stats[:count_based].each do |table, count|
          Rails.logger.info "    #{table} (count): #{count}" if count > 0
        end
      end
    end
  end
end
