require "async"

module RailsPulse
  module Tracker
    # PG::Connection::PQTRANS_INERROR (libpq enum value 3) — the connection's transaction
    # was aborted by a DB-level error and no ROLLBACK has been issued yet. Defined as a
    # constant to avoid a hard dependency on the pg gem. The full enum is:
    #   PQTRANS_IDLE=0, PQTRANS_ACTIVE=1, PQTRANS_INTRANS=2, PQTRANS_INERROR=3, PQTRANS_UNKNOWN=4
    PG_TRANSACTION_INERROR = 3
    private_constant :PG_TRANSACTION_INERROR

    class << self
      def track_request(data)
        return if RequestStore.store[:skip_recording_rails_pulse_activity]

        if RailsPulse.configuration.async
          Async { perform_tracking(data) }
        else
          perform_tracking(data)
        end
      end

      def healthy?
        RailsPulse::ApplicationRecord.connection.execute("SELECT 1")
        true
      rescue
        false
      end

      private

      def perform_tracking(data)
        RailsPulse::ApplicationRecord.connection_pool.with_connection do |conn|
          clear_aborted_transaction(conn)
          RequestStore.store[:skip_recording_rails_pulse_activity] = true

          route = RailsPulse::Route.find_or_create_for_request(data[:method], data[:path], controller_action: data[:controller_action])

          request = RailsPulse::Request.create!(
            route: route,
            method: data[:method],
            duration: data[:duration],
            status: data[:status],
            is_error: data[:is_error],
            request_uuid: data[:request_uuid],
            controller_action: data[:controller_action],
            occurred_at: data[:occurred_at],
            response_size_bytes: data[:response_size_bytes]
          )

          ops = data[:operations] || []
          RailsPulse::Operation.persist_bulk(ops, request_id: request.id)

          request
        rescue => e
          log_error(e)
          nil
        ensure
          RequestStore.store[:skip_recording_rails_pulse_activity] = false
        end
      end

      def clear_aborted_transaction(conn)
        raw = conn.raw_connection
        # Non-PostgreSQL adapters don't expose transaction_status, so this is a no-op for them.
        return unless raw.respond_to?(:transaction_status) && raw.transaction_status == PG_TRANSACTION_INERROR
        conn.rollback_db_transaction
      rescue ActiveRecord::StatementInvalid
        nil
      end

      def log_error(error)
        RailsPulse.logger.error("Failed to persist tracking data: #{error.message}")
        RailsPulse.logger.error(error.backtrace.join("\n")) if RailsPulse.logger.debug?
      end
    end
  end
end
