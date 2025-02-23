module RailsPulse
  module Subscribers
    class OperationSubscriber
      def self.subscribe!
        # Helper method to clean SQL labels by removing Rails comments
        def self.clean_sql_label(sql)
          return sql unless sql
          # Remove Rails SQL comments like /*action='search',application='Dummy',controller='home'*/
          sql.gsub(/\/\*[^*]*\*\//, '').strip
        end

        # Helper method to capture operation data
        def self.capture_operation(event_name, start, finish, payload, operation_type, label_key = nil)
          return if RequestStore.store[:skip_recording_rails_pulse_activity]

          request_id = RequestStore.store[:rails_pulse_request_id]
          return unless request_id

          # Skip RailsPulse-related operations to prevent recursion
          if operation_type == "sql"
            sql = payload[:sql]
            return if sql&.include?("rails_pulse_")
          end

          label = case label_key
                  when :sql then clean_sql_label(payload[:sql])
                  when :template then payload[:identifier] || payload[:template]
                  when :partial then payload[:identifier] || payload[:partial]
                  when :controller then "#{payload[:controller]}##{payload[:action]}"
                  when :cache then payload[:key]
                  else payload[label_key] || event_name
                  end

          operation_data = {
            request_id: request_id,
            operation_type: operation_type,
            label: label,
            duration: (finish - start) * 1000,
            codebase_location: payload[:file] || caller_locations(3,1).first&.path,
            start_time: start.to_f,
            occurred_at: Time.zone.at(start),
          }

          RequestStore.store[:rails_pulse_operations] ||= []
          RequestStore.store[:rails_pulse_operations] << operation_data
        end

        # SQL queries
        ActiveSupport::Notifications.subscribe "sql.active_record" do |name, start, finish, id, payload|
          begin
            next if payload[:name] == "SCHEMA"
            capture_operation(name, start, finish, payload, "sql", :sql)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in SQL subscriber: #{e.class} - #{e.message}"
          end
        end

        # Controller action processing
        ActiveSupport::Notifications.subscribe "process_action.action_controller" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "controller", :controller)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in controller subscriber: #{e.class} - #{e.message}"
          end
        end

        # Template rendering
        ActiveSupport::Notifications.subscribe "render_template.action_view" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "template", :template)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in template subscriber: #{e.class} - #{e.message}"
          end
        end

        # Partial rendering
        ActiveSupport::Notifications.subscribe "render_partial.action_view" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "partial", :partial)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in partial subscriber: #{e.class} - #{e.message}"
          end
        end

        # Layout rendering
        ActiveSupport::Notifications.subscribe "render_layout.action_view" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "layout", :template)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in layout subscriber: #{e.class} - #{e.message}"
          end
        end

        # Cache operations
        ActiveSupport::Notifications.subscribe "cache_read.active_support" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "cache_read", :cache)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in cache_read subscriber: #{e.class} - #{e.message}"
          end
        end

        ActiveSupport::Notifications.subscribe "cache_write.active_support" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "cache_write", :cache)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in cache_write subscriber: #{e.class} - #{e.message}"
          end
        end

        # HTTP client requests (if using Net::HTTP)
        ActiveSupport::Notifications.subscribe "request.net_http" do |name, start, finish, id, payload|
          begin
            label = "#{payload[:method]} #{payload[:uri]}"
            operation_data = {
              request_id: RequestStore.store[:rails_pulse_request_id],
              operation_type: "http",
              label: label,
              duration: (finish - start) * 1000,
              codebase_location: caller_locations(2,1).first&.path,
              start_time: start.to_f,
              occurred_at: Time.zone.at(start),
            }

            if operation_data[:request_id]
              RequestStore.store[:rails_pulse_operations] ||= []
              RequestStore.store[:rails_pulse_operations] << operation_data
            end
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in HTTP subscriber: #{e.class} - #{e.message}"
          end
        end

        # Active Job processing
        ActiveSupport::Notifications.subscribe "perform.active_job" do |name, start, finish, id, payload|
          begin
            label = "#{payload[:job].class.name}"
            operation_data = {
              request_id: RequestStore.store[:rails_pulse_request_id],
              operation_type: "job",
              label: label,
              duration: (finish - start) * 1000,
              codebase_location: caller_locations(2,1).first&.path,
              start_time: start.to_f,
              occurred_at: Time.zone.at(start),
            }

            if operation_data[:request_id]
              RequestStore.store[:rails_pulse_operations] ||= []
              RequestStore.store[:rails_pulse_operations] << operation_data
            end
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in job subscriber: #{e.class} - #{e.message}"
          end
        end

        # Collection rendering (for rendering collections)
        ActiveSupport::Notifications.subscribe "render_collection.action_view" do |name, start, finish, id, payload|
          begin
            capture_operation(name, start, finish, payload, "collection", :template)
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in collection subscriber: #{e.class} - #{e.message}"
          end
        end

        # Action Mailer
        ActiveSupport::Notifications.subscribe "deliver.action_mailer" do |name, start, finish, id, payload|
          begin
            label = "#{payload[:mailer]}##{payload[:action]}"
            operation_data = {
              request_id: RequestStore.store[:rails_pulse_request_id],
              operation_type: "mailer",
              label: label,
              duration: (finish - start) * 1000,
              codebase_location: caller_locations(2,1).first&.path,
              start_time: start.to_f,
              occurred_at: Time.zone.at(start),
            }

            if operation_data[:request_id]
              RequestStore.store[:rails_pulse_operations] ||= []
              RequestStore.store[:rails_pulse_operations] << operation_data
            end
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in mailer subscriber: #{e.class} - #{e.message}"
          end
        end

        # Active Storage
        ActiveSupport::Notifications.subscribe "service_upload.active_storage" do |name, start, finish, id, payload|
          begin
            label = "Upload: #{payload[:key]}"
            operation_data = {
              request_id: RequestStore.store[:rails_pulse_request_id],
              operation_type: "storage",
              label: label,
              duration: (finish - start) * 1000,
              codebase_location: caller_locations(2,1).first&.path,
              start_time: start.to_f,
              occurred_at: Time.zone.at(start),
            }

            if operation_data[:request_id]
              RequestStore.store[:rails_pulse_operations] ||= []
              RequestStore.store[:rails_pulse_operations] << operation_data
            end
          rescue => e
            Rails.logger.error "[RailsPulse] Exception in storage subscriber: #{e.class} - #{e.message}"
          end
        end
      end
    end
  end
end
